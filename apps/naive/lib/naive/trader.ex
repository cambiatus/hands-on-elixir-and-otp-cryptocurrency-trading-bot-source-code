defmodule Naive.Trader do
  use GenServer, restart: :temporary

  alias Core.Struct.{KlineEvent, OrderEvent, TradeEvent}
  alias Naive.Strategy

  require Logger

  @logger Application.compile_env(:core, :logger)
  @pubsub_client Application.compile_env(:core, :pubsub_client)
  @registry :naive_traders

  defmodule State do
    @enforce_keys [:settings, :positions, :data]
    defstruct [:settings, positions: [], data: %{}]
  end

  @spec start_link(binary) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(symbol) do
    symbol = String.upcase(symbol)

    GenServer.start_link(
      __MODULE__,
      symbol,
      name: via_tuple(symbol)
    )
  end

  def init(symbol) do
    @logger.info("Initializing new trader for #{symbol}")

    @pubsub_client.subscribe(
      Core.PubSub,
      "KLINE_EVENTS:#{symbol}"
    )

    {:ok, nil, {:continue, {:start_position, symbol}}}
  end

  def handle_continue({:start_position, symbol}, _state) do
    settings = Strategy.fetch_symbol_settings(symbol)
    positions = [Strategy.generate_fresh_position(settings)]

    # TODO: Remove hardcoded interval and number of datapoints

    initial_data =
      case Core.Exchange.Binance.get_recent_klines_data(symbol, "1m", 50) do
        {:ok, initial_data} ->
          Map.put(initial_data, :complete, List.duplicate(true, 50))

        {:error, error} ->
          Logger.info("Could not get historical data for #{symbol} at 1m")
          {:stop, error, nil}
      end

    {:noreply, %State{settings: settings, positions: positions, data: initial_data}}
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

    case Naive.Strategy.execute(kline_event, state.positions, state.settings, data) do
      {:ok, updated_positions} ->
        {:noreply, %{state | positions: updated_positions, data: data}}

      :exit ->
        {:ok, _settings} = Strategy.update_status(kline_event.symbol, "off")
        Logger.info("Trading for #{kline_event.symbol} stopped")
        {:stop, :normal, state}
    end
  end

  def handle_info(%OrderEvent{} = order_event, %State{} = state) do
    case Naive.Strategy.execute(order_event, state.positions, state.settings) do
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

  defp via_tuple(symbol) do
    {:via, Registry, {@registry, symbol}}
  end
end
