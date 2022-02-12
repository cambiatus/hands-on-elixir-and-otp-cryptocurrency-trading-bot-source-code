defmodule Naive.Trader do
  use GenServer, restart: :temporary

  alias Core.Struct.TradeEvent

  require Logger

  @logger Application.get_env(:core, :logger)
  @pubsub_client Application.get_env(:core, :pubsub_client)

  defmodule State do
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

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{id: id, symbol: symbol} = state) do
    symbol = String.upcase(symbol)

    @logger.info("Initializing a new trader(#{id}) for #{symbol}")

    @pubsub_client.subscribe(
      Core.PubSub,
      "TRADE_EVENTS:#{symbol}"
    )

    {:ok, state}
  end

  def handle_info(%TradeEvent{} = trade_event, %State{} = state) do
    case Naive.Strategy.execute(trade_event, state) do
      {:ok, new_state} -> {:noreply, new_state}
      :exit -> {:stop, :normal, state}
    end
  end
end
