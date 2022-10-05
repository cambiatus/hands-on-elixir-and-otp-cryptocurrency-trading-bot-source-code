defmodule Naive.Trader do
  use GenServer, restart: :temporary

  alias Core.Struct.{KlineEvent, OrderEvent, TradeEvent}
  alias Naive.Strategy
  alias Naive.Schema.Traders
  alias Naive.Repo

  require Logger

  @logger Application.compile_env(:core, :logger)
  @pubsub_client Application.compile_env(:core, :pubsub_client)
  @registry :naive_traders

  defmodule State do
    @enforce_keys [:trader_id, :settings, :positions, :data]
    defstruct [:trader_id, :settings, positions: [], data: %{}]
  end

  @spec start_link(binary) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(id) do
    GenServer.start_link(
      __MODULE__,
      id,
      name: via_tuple(id)
    )
  end

  def init(trader_id) do
    settings = fetch_settings(trader_id)

    @logger.info("Initializing new trader for #{settings.symbol}, id: #{trader_id}")

    @pubsub_client.subscribe(
      Core.PubSub,
      "KLINE_EVENTS:#{settings.symbol}#{settings.interval}"
    )

    @pubsub_client.subscribe(
      Core.PubSub,
      "ORDER_EVENTS:#{settings.symbol}"
    )

    {:ok, trader_id, {:continue, {:start_position, settings}}}
  end

  def handle_continue(
        {:start_position, %{symbol: symbol, strategy: strategy, interval: interval, args: args}},
        trader_id
      ) do
    settings =
      Strategy.fetch_symbol_settings(symbol)
      |> Map.put(:strategy, strategy)
      |> Map.put(:strategy_args, args)

    positions = [Strategy.generate_fresh_position(settings)]

    case Strategies.start_strategy(strategy, symbol, interval, args) do
      {:ok, initial_data} ->
        {:noreply,
         %State{
           trader_id: trader_id,
           settings: settings,
           positions: positions,
           data: initial_data
         }}

      {:error, error} ->
        {:stop, error, nil}
    end
  end

  def notify(:settings_updated, settings) do
    call_trader(settings.symbol, {:update_settings, settings})
  end

  def get_positions(symbol) do
    call_trader(symbol, {:get_positions, symbol})
  end

  def handle_call(
        {:update_settings, new_settings},
        _,
        state
      ) do
    {:reply, :ok, %{state | settings: new_settings}}
  end

  def handle_call(
        {:get_positions, _symbol},
        _,
        state
      ) do
    {:reply, state.positions, state}
  end

  def handle_info(%TradeEvent{} = trade_event, %State{} = state) do
    case Naive.Strategy.execute(trade_event, state.positions, state.settings) do
      {:ok, updated_positions} ->
        {:noreply, %{state | positions: updated_positions}}

      :exit ->
        {:ok, _settings} = Strategy.update_status(trade_event.symbol, "off")
        Logger.info("Trading for #{trade_event.symbol} stopped")
        {:stop, :normal, state}
    end
  end

  def handle_info(%KlineEvent{} = kline_event, %State{data: data} = state) do
    data = append_kline(kline_event, data)

    case Naive.Strategy.execute(
           kline_event,
           state.positions,
           state.settings,
           data,
           state.trader_id
         ) do
      {:ok, updated_positions} ->
        {:noreply, %{state | positions: updated_positions, data: data}}

      :exit ->
        {:ok, _settings} = Strategy.update_status(kline_event.symbol, "off")
        Logger.info("Trading for #{kline_event.symbol} stopped")
        {:stop, :normal, state}
    end
  end

  def handle_info(%OrderEvent{} = order_event, %State{data: data} = state) do
    case Naive.Strategy.execute(
           order_event,
           state.positions,
           state.settings,
           data,
           state.trader_id
         ) do
      {:ok, updated_positions} ->
        {:noreply, %{state | positions: updated_positions}}

      :exit ->
        {:ok, _settings} = Strategy.update_status(order_event.symbol, "off")
        Logger.info("Trading for #{order_event.symbol} stopped")
        {:stop, :normal, state}
    end
  end

  defp append_kline(kline, data) do
    data
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, appended ->
      Map.put(appended, key, Map.get(data, key) ++ [Map.get(kline, key)])
    end)
  end

  defp call_trader(symbol, data) do
    case Registry.lookup(@registry, symbol) do
      [{pid, _}] ->
        GenServer.call(
          pid,
          data
        )

      _ ->
        Logger.warn("Unable to locate trader process assigned to #{symbol}")
        {:error, :unable_to_locate_trader}
    end
  end

  defp fetch_settings(id) do
    settings = Repo.get(Traders, id)

    %{
      settings
      | strategy: String.to_atom(settings.strategy),
        args: Poison.decode!(settings.args),
        interval: to_string(settings.interval)
    }
  end

  defp via_tuple(args) do
    {:via, Registry, {@registry, args}}
  end
end
