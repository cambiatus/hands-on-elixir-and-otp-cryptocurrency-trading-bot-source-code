defmodule Naive.Strategy do
  alias Core.Exchange
  alias Core.Struct.{OrderEvent, TradeEvent}
  alias Decimal, as: D
  alias Naive.Schema.Settings

  require Logger

  @exchange_client Application.compile_env(:naive, :exchange_client)
  @logger Application.compile_env(:core, :logger)
  @repo Application.compile_env(:naive, :repo)

  defmodule Position do
    @enforce_keys [
      :id,
      :symbol,
      :budget,
      :buy_down_interval,
      :profit_interval,
      :rebuy_interval,
      :rebuy_notified,
      :tick_size,
      :step_size
    ]
    defstruct [
      :id,
      :symbol,
      :budget,
      :buy_order,
      :sell_order,
      :buy_down_interval,
      :profit_interval,
      :rebuy_interval,
      :rebuy_notified,
      :tick_size,
      :step_size
    ]
  end

  def execute(%TradeEvent{} = trade_event, positions, settings) do
    generate_decisions(positions, [], trade_event, settings)
    |> Enum.map(fn {decision, position} ->
      Task.async(fn -> execute_decision(decision, position, settings) end)
    end)
    |> Task.await_many()
    |> then(&parse_results/1)
  end

  def execute(%OrderEvent{} = order_event, positions, settings) do
    generate_decisions(positions, [], order_event, settings)
    |> Enum.map(fn {decision, position} ->
      Task.async(fn -> execute_decision(decision, position, settings) end)
    end)
    |> Task.await_many()
    |> then(&parse_results/1)
  end

  def parse_results([]) do
    :exit
  end

  def parse_results([_ | _] = results) do
    results
    |> Enum.map(fn {:ok, new_position} -> new_position end)
    |> then(&{:ok, &1})
  end

  def generate_decisions([], generated_results, _trade_event, _settings) do
    generated_results
  end

  def generate_decisions([position | rest] = positions, generated_results, trade_event, settings) do
    current_positions = positions ++ (generated_results |> Enum.map(&elem(&1, 0)))

    case generate_decision(trade_event, position, current_positions, settings) do
      :exit ->
        generate_decisions(rest, generated_results, trade_event, settings)

      :rebuy ->
        generate_decisions(
          rest,
          [{:skip, %{position | rebuy_notified: true}}, {:rebuy, position}] ++ generated_results,
          trade_event,
          settings
        )

      :update_buy_position ->
        current_buy_order = update_order_position(position, :buy_order, trade_event.order_status)

        generate_decisions(
          rest,
          [{:skip, %{position | buy_order: current_buy_order}}] ++ generated_results,
          trade_event,
          settings
        )

      :update_sell_position ->
        current_sell_order =
          update_order_position(position, :sell_order, trade_event.order_status)

        generate_decisions(
          rest,
          [{:skip, %{position | sell_order: current_sell_order}}] ++ generated_results,
          trade_event,
          settings
        )

      decision ->
        generate_decisions(
          rest,
          [{decision, position} | generated_results],
          trade_event,
          settings
        )
    end
  end

  def update_order_position(position, side, new_status) do
    unless new_status == "NEW" do
      @logger.info(
        "Position (#{position.symbol}/#{position.id}): The " <>
          "#{atom_to_side(side)} has been #{new_status}"
      )
    end

    new_status = status_to_atom(new_status)

    position
    |> Map.get(side)
    |> Map.put(:status, new_status)
  end

  defp atom_to_side(:buy_order), do: "BUY order"
  defp atom_to_side(:sell_order), do: "SELL order"

  defp status_to_atom("NEW"), do: :new
  defp status_to_atom("FILLED"), do: :filled
  defp status_to_atom("PARTIALLY_FILLED"), do: :partially_filled
  defp status_to_atom("CANCELLED"), do: :cancelled

  def generate_decision(
        %TradeEvent{price: price},
        %Position{
          budget: budget,
          buy_order: nil,
          buy_down_interval: buy_down_interval,
          tick_size: tick_size,
          step_size: step_size
        },
        _positions,
        _settings
      ) do
    price =
      Strategies.Caller.call_python(:naive, :calculate_buy_price, [
        price,
        D.to_string(buy_down_interval),
        tick_size
      ])
      |> elem(1)
      |> to_string()

    quantity =
      Strategies.Caller.call_python(:naive, :calculate_quantity, [
        D.to_string(budget),
        price,
        step_size
      ])
      |> elem(1)
      |> to_string()

    {:place_buy_order, price, quantity}
  end

  def generate_decision(
        %OrderEvent{
          order_id: order_id
        },
        %Position{
          buy_order: %Exchange.Order{
            id: order_id,
            status: :filled
          },
          sell_order: %Exchange.Order{}
        },
        _positions,
        _settings
      ) do
    :skip
  end

  def generate_decision(
        %OrderEvent{},
        %Position{
          buy_order: %Exchange.Order{
            status: :filled,
            price: buy_price
          },
          sell_order: nil,
          profit_interval: profit_interval,
          tick_size: tick_size
        },
        _positions,
        _settings
      ) do
    sell_price =
      Strategies.Caller.call_python(:naive, :calculate_sell_price, [
        buy_price,
        to_string(profit_interval),
        tick_size
      ])
      |> elem(1)
      |> to_string()

    {:place_sell_order, sell_price}
  end

  def generate_decision(
        %OrderEvent{
          order_id: order_id
        },
        %Position{
          buy_order: %Exchange.Order{
            id: order_id
          }
        },
        _positions,
        _settings
      ) do
    :update_buy_position
  end

  def generate_decision(
        %OrderEvent{},
        %Position{
          sell_order: %Exchange.Order{
            status: :filled
          }
        },
        _positions,
        settings
      ) do
    if settings.status != "shutdown" do
      :finished
    else
      :exit
    end
  end

  def generate_decision(
        %OrderEvent{
          order_id: order_id
        },
        %Position{
          sell_order: %Exchange.Order{
            id: order_id
          }
        },
        _positions,
        _settings
      ) do
    :update_sell_position
  end

  def generate_decision(
        %TradeEvent{
          price: current_price
        },
        %Position{
          buy_order: %Exchange.Order{
            price: buy_price
          },
          rebuy_interval: rebuy_interval,
          rebuy_notified: false
        },
        positions,
        settings
      ) do
    if trigger_rebuy?(buy_price, current_price, rebuy_interval) &&
         settings.status != "shutdown" &&
         length(positions) < settings.chunks do
      :rebuy
    else
      :skip
    end
  end

  def generate_decision(%TradeEvent{}, %Position{}, _positions, _settings) do
    :skip
  end

  def generate_decision(%OrderEvent{}, %Position{}, _positions, _settings) do
    :skip
  end

  def calculate_sell_price(buy_price, profit_interval, tick_size) do
    fee = "1.001"
    original_price = D.mult(buy_price, fee)

    net_target_price =
      D.mult(
        original_price,
        D.add("1.0", profit_interval)
      )

    gross_target_price = D.mult(net_target_price, fee)

    D.to_string(
      D.mult(
        D.div_int(gross_target_price, tick_size),
        tick_size
      ),
      :normal
    )
  end

  def calculate_buy_price(current_price, buy_down_interval, tick_size) do
    # not necessarily legal price
    exact_buy_price =
      D.sub(
        current_price,
        D.mult(current_price, buy_down_interval)
      )

    D.to_string(
      D.mult(
        D.div_int(exact_buy_price, tick_size),
        tick_size
      ),
      :normal
    )
  end

  def calculate_quantity(budget, price, step_size) do
    # not necessarily legal quantity
    exact_target_quantity = D.div(budget, price)

    D.to_string(
      D.mult(
        D.div_int(exact_target_quantity, step_size),
        step_size
      ),
      :normal
    )
  end

  def trigger_rebuy?(buy_price, current_price, rebuy_interval) do
    rebuy_price =
      D.sub(
        buy_price,
        D.mult(buy_price, rebuy_interval)
      )

    D.lt?(current_price, rebuy_price)
  end

  defp execute_decision(
         {:place_buy_order, price, quantity},
         %Position{
           id: id,
           symbol: symbol
         } = position,
         _settings
       ) do
    @logger.info(
      "Position (#{symbol}/#{id}): " <>
        "Placing a BUY order @ #{price}, quantity: #{quantity}"
    )

    case @exchange_client.order_limit_buy(symbol, quantity, price) do
      {:ok, %Exchange.Order{} = order} ->
        {:ok, %{position | buy_order: order}}

      {:error, error} ->
        @logger.info("Error when placing BUY order. Reason: #{error}")
        {:error, error}
    end
  end

  defp execute_decision(
         {:place_sell_order, sell_price},
         %Position{
           id: id,
           symbol: symbol,
           buy_order: %Exchange.Order{
             quantity: quantity
           }
         } = position,
         _settings
       ) do
    @logger.info(
      "Position (#{symbol}/#{id}): The BUY order is now filled. " <>
        "Placing a SELL order @ #{sell_price}, quantity: #{quantity}"
    )

    case @exchange_client.order_limit_sell(symbol, quantity, sell_price) do
      {:ok, %Exchange.Order{} = order} ->
        {:ok, %{position | sell_order: order}}

      {:error, error} ->
        @logger.info("Error when placing SELL order. Reason: #{error}")
        {:error, error}
    end
  end

  defp execute_decision(
         :finished,
         %Position{
           id: id,
           symbol: symbol
         },
         settings
       ) do
    new_position = generate_fresh_position(settings)

    @logger.info("Position (#{symbol}/#{id}): Trade cycle finished")

    {:ok, new_position}
  end

  defp execute_decision(
         :rebuy,
         %Position{
           id: id,
           symbol: symbol
         },
         settings
       ) do
    new_position = generate_fresh_position(settings)

    @logger.info("Position (#{symbol}/#{id}): Rebuy triggered. Starting new position")

    {:ok, new_position}
  end

  defp execute_decision(:skip, state, _settings) do
    {:ok, state}
  end

  def fetch_symbol_settings(symbol) do
    {:ok, filters} = @exchange_client.fetch_symbol_filters(symbol)
    db_settings = @repo.get_by!(Settings, symbol: symbol)

    Map.merge(
      filters |> Map.from_struct(),
      db_settings |> Map.from_struct()
    )
  end

  def generate_fresh_position(settings, id \\ :os.system_time(:millisecond)) do
    %{
      struct(Position, settings)
      | id: id,
        budget: D.div(settings.budget, settings.chunks),
        rebuy_notified: false
    }
  end

  def update_status(symbol, status)
      when is_binary(symbol) and is_binary(status) do
    @repo.get_by(Settings, symbol: symbol)
    |> Ecto.Changeset.change(%{status: status})
    |> @repo.update()
  end
end
