defmodule Naive.Strategy do
  alias Core.Exchange
  alias Core.Struct.{KlineEvent, OrderEvent, TradeEvent}
  alias Decimal, as: D
  alias Naive.Schema.Settings

  require Logger

  @exchange_client Application.compile_env(:naive, :exchange_client)
  @logger Application.compile_env(:core, :logger)
  @repo Application.compile_env(:naive, :repo)
  @pubsub_client Application.compile_env(:core, :pubsub_client)

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
      :step_size,
      :position
    ]
  end

  def execute(%TradeEvent{} = trade_event, positions, settings, data, trader_id) do
    generate_decisions(positions, [], trade_event, settings, data)
    |> Enum.map(fn {decision, position} ->
      Task.async(fn -> execute_decision(decision, position, settings, trader_id) end)
    end)
    |> Task.await_many()
    |> then(&parse_results/1)
  end

  def execute(%OrderEvent{} = order_event, positions, settings, data, trader_id) do
    generate_decisions(positions, [], order_event, settings, data)
    |> Enum.map(fn {decision, position} ->
      Task.async(fn -> execute_decision(decision, position, settings, trader_id) end)
    end)
    |> Task.await_many()
    |> then(&parse_results/1)
  end

  def execute(%KlineEvent{} = kline_event, positions, settings, data, trader_id) do
    generate_decisions(positions, [], kline_event, settings, data)
    |> Enum.map(fn {decision, position} ->
      Task.async(fn -> execute_decision(decision, position, settings, trader_id) end)
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

  def generate_decisions([], generated_results, _trade_event, _settings, _data) do
    generated_results
  end

  def generate_decisions(
        [position | rest] = positions,
        generated_results,
        trade_event,
        settings,
        data
      ) do
    current_positions = positions ++ (generated_results |> Enum.map(&elem(&1, 0)))

    case generate_decision(trade_event, position, current_positions, settings, data) do
      :exit ->
        generate_decisions(rest, generated_results, trade_event, settings, data)

      :rebuy ->
        generate_decisions(
          rest,
          [{:skip, %{position | rebuy_notified: true}}, {:rebuy, position}] ++ generated_results,
          trade_event,
          settings,
          data
        )

      :update_buy_position ->
        current_buy_order =
          update_order_position(
            position,
            :buy_order,
            trade_event
          )

        generate_decisions(
          rest,
          [{:skip, %{position | buy_order: current_buy_order}}] ++ generated_results,
          trade_event,
          settings,
          data
        )

      :update_sell_position ->
        current_sell_order =
          update_order_position(
            position,
            :sell_order,
            trade_event
          )

        generate_decisions(
          rest,
          [{:skip, %{position | sell_order: current_sell_order}}] ++ generated_results,
          trade_event,
          settings,
          data
        )

      decision ->
        generate_decisions(
          rest,
          [{decision, position} | generated_results],
          trade_event,
          settings,
          data
        )
    end
  end

  def update_order_position(position, side, order_event) do
    new_status = status_to_atom(order_event.order_status)

    unless order_event.order_status == "NEW" do
      @logger.info(
        "Position (#{position.symbol}/#{position.id}): The " <>
          "#{order_event.side} has been #{order_event.order_status}"
      )
    end

    broadcast_order(%Exchange.Order{
      id: order_event.order_id,
      symbol: position.symbol,
      price: order_event.original_price,
      quantity: order_event.original_quantity,
      status: order_event.order_status,
      side: order_event.side,
      realized_quantity: order_event.order_filled_accumulated_quantity,
      average_price: order_event.average_price,
      timestamp: order_event.event_time
    })

    position
    |> Map.get(side)
    |> Map.put(:status, new_status)
  end

  defp status_to_atom("NEW"), do: :new
  defp status_to_atom("FILLED"), do: :filled
  defp status_to_atom("PARTIALLY_FILLED"), do: :partially_filled
  defp status_to_atom("CANCELLED"), do: :cancelled

  # TODO: Reimplement position pattern matching as estabilished previously on the project
  # instead of simlpy matching on this one clause and using the number outputed by the strategy

  def generate_decision(
        %KlineEvent{},
        %Position{
          position: position
        },
        _positions,
        %{strategy: strategy, strategy_args: strategy_args} = _settings,
        data
      ) do
    case Strategies.execute_strategy(strategy, data, position, strategy_args) do
      {:ok, [["BUY", "MARKET", quantity], position]} ->
        {:place_buy_order, "MARKET", quantity, position}

      {:ok, [["BUY", "LIMIT", price, quantity], position]} ->
        {:place_buy_order, "LIMIT", price, quantity, position}

      {:ok, [["SELL", "MARKET", quantity], position]} ->
        {:place_sell_order, "MARKET", quantity, position}

      {:ok, [["SELL", "LIMIT", price, quantity], position]} ->
        {:place_sell_order, "LIMIT", price, quantity, position}

      {:ok, _data = [[], _position]} ->
        :skip

      :error ->
        :error
    end
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
        _settings,
        _data
      ) do
    :skip
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
        _settings,
        _data
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
        settings,
        _data
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
        _settings,
        _data
      ) do
    :update_sell_position
  end

  def generate_decision(
        %KlineEvent{
          close_price: current_price
        },
        %Position{
          buy_order: %Exchange.Order{
            price: buy_price
          },
          rebuy_interval: rebuy_interval,
          rebuy_notified: false
        },
        positions,
        settings,
        _data
      ) do
    if trigger_rebuy?(buy_price, current_price, rebuy_interval) &&
         settings.status != "shutdown" &&
         length(positions) < settings.chunks do
      :skip
    else
      :skip
    end
  end

  def generate_decision(_event_struct, %Position{}, _positions, _settings, _data) do
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
         {:place_buy_order, "LIMIT", price, quantity, python_position},
         %Position{
           id: id,
           symbol: symbol,
           tick_size: tick_size,
           step_size: step_size
         } = position,
         _settings,
         trader_id
       ) do
    [price, quantity] =
      order_helper(symbol, id, "LIMIT", "BUY", price, quantity, tick_size, step_size)

    case @exchange_client.order_limit_buy(symbol, quantity, price) do
      {:ok, %Exchange.Order{} = order} ->
        new_order(order, trader_id)
        {:ok, %{position | buy_order: order, position: python_position}}

      {:error, error} ->
        @logger.info("Error when placing BUY order. Reason: #{error}")
        {:error, error}
    end
  end

  defp execute_decision(
         {:place_buy_order, "MARKET", quantity, python_position},
         %Position{
           id: id,
           symbol: symbol,
           step_size: step_size
         } = position,
         _settings,
         trader_id
       ) do
    [_, quantity] = order_helper(symbol, id, "MARKET", "BUY", nil, quantity, nil, step_size)

    case @exchange_client.order_market_buy(symbol, quantity) do
      {:ok, %Exchange.Order{} = order} ->
        new_order(order, trader_id)
        {:ok, %{position | buy_order: order, position: python_position}}

      {:error, error} ->
        @logger.info("Error when placing BUY order. Reason: #{error}")
        {:error, error}
    end
  end

  defp execute_decision(
         {:place_sell_order, sell_price, python_position},
         %Position{
           id: id,
           symbol: symbol,
           tick_size: tick_size,
           step_size: step_size,
           buy_order: %Exchange.Order{
             quantity: quantity
           }
         } = position,
         _settings,
         trader_id
       ) do
    [sell_price, quantity] =
      order_helper(symbol, id, "LIMIT", "SELL", sell_price, quantity, tick_size, step_size)

    case @exchange_client.order_limit_sell(symbol, quantity, sell_price) do
      {:ok, %Exchange.Order{} = order} ->
        new_order(order, trader_id)
        {:ok, %{position | sell_order: order, position: python_position}}

      {:error, error} ->
        @logger.info("Error when placing SELL order. Reason: #{error}")
        {:error, error}
    end
  end

  defp execute_decision(
         {:place_sell_order, "MARKET", quantity, python_position},
         %Position{
           id: id,
           symbol: symbol,
           step_size: step_size
         } = position,
         _settings,
         trader_id
       ) do
    [_, quantity] = order_helper(symbol, id, "MARKET", "SELL", nil, quantity, nil, step_size)

    case @exchange_client.order_market_sell(symbol, quantity) do
      {:ok, %Exchange.Order{} = order} ->
        new_order(order, trader_id)
        {:ok, %{position | sell_order: order, position: python_position}}

      {:error, error} ->
        @logger.info("Error when placing BUY order. Reason: #{error}")
        {:error, error}
    end
  end

  defp execute_decision(
         :finished,
         %Position{
           id: id,
           symbol: symbol
         },
         settings,
         _trader_id
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
         settings,
         _trader_id
       ) do
    new_position = generate_fresh_position(settings)

    @logger.info("Position (#{symbol}/#{id}): Rebuy triggered. Starting new position")

    {:ok, new_position}
  end

  defp execute_decision(:skip, state, _settings, _trader_id) do
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

  defp order_helper(
         symbol,
         id,
         "LIMIT",
         side,
         price,
         quantity,
         tick_size,
         step_size
       ) do
    price = validate_precision(price, tick_size)

    # TODO: Remove hardcoding When quantity calculculation is implemented in the strategy module

    quantity = 10 * step_size
    quantity = validate_precision(quantity, step_size)

    @logger.info(
      "Position (#{symbol}/#{id}): " <>
        "Placing a LIMIT #{side} order @ #{price}, quantity: #{quantity}"
    )

    [price, quantity]
  end

  defp order_helper(
         symbol,
         id,
         "MARKET",
         side,
         nil = _price,
         quantity,
         nil = _tick_size,
         step_size
       ) do
    # quantity = validate_precision(quantity, step_size)
    {:ok, mult} = D.cast(1000)
    {:ok, step_size} = D.cast(step_size)

    quantity = D.to_string(D.mult(mult, step_size), :normal)

    @logger.info(
      "Position (#{symbol}/#{id}): " <>
        "Placing a MARKET #{side} order, quantity: #{quantity}"
    )

    [nil, quantity]
  end

  defp validate_precision(exact_number, precision) do
    D.to_string(
      D.mult(
        D.div_int(exact_number, precision),
        precision
      ),
      :normal
    )
  end

  def generate_fresh_position(settings, id \\ :os.system_time(:millisecond)) do
    %{
      struct(Position, settings)
      | id: id,
        budget: D.div(settings.budget, settings.chunks),
        rebuy_notified: false,
        position: 0
    }
  end

  def update_status(id, status)
      when is_binary(status) do
    @repo.get_by(Traders: id)
    |> Ecto.Changeset.change(%{status: status})
    |> @repo.update()
  end

  defp new_order(%Exchange.Order{} = order, trader_id) do
    order
    |> Map.put(:trader_id, trader_id)
    |> broadcast_order()
  end

  defp broadcast_order(%Exchange.Order{} = order) do
    @pubsub_client.broadcast(
      Core.PubSub,
      "ORDERS:#{order.symbol}",
      order
    )
  end
end
