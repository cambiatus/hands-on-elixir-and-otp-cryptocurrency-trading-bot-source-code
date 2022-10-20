defmodule DataWarehouse.Subscriber.Worker do
  use GenServer

  alias Core.Struct.{KlineEvent, TradeEvent}

  alias DataWarehouse.Schema.Order
  alias DataWarehouse.Repo

  require Logger

  defmodule State do
    @enforce_keys [:topic]
    defstruct [:topic]
  end

  def start_link(topic) do
    GenServer.start_link(
      __MODULE__,
      topic,
      name: via_tuple(topic)
    )
  end

  def init(topic) do
    Logger.info("DataWarehouse worker is subscribing to #{topic}")

    Phoenix.PubSub.subscribe(
      Core.PubSub,
      topic
    )

    {:ok,
     %State{
       topic: topic
     }}
  end

  def handle_info(%TradeEvent{} = trade_event, state) do
    opts =
      trade_event
      |> Map.from_struct()

    struct!(DataWarehouse.Schema.TradeEvent, opts)
    |> DataWarehouse.Repo.insert()

    {:noreply, state}
  end

  def handle_info(%KlineEvent{} = kline_event, state) do
    opts =
      kline_event
      |> Map.from_struct()

    struct!(DataWarehouse.Schema.KlineEvent, opts)
    |> DataWarehouse.Repo.insert()

    {:noreply, state}
  end

  def handle_info(%Core.Exchange.Order{} = order, state) do
    data =
      %{
        id: order.id,
        symbol: order.symbol,
        price: order.price,
        quantity: order.quantity,
        side: order.side,
        status: order.status,
        type: order.type,
        time_in_force: order.time_in_force,
        average_price: order.average_price,
        order_id: order.id,
        realized_quantity: order.realized_quantity,
        position_side: order.position_side,
        timestamp: order.timestamp,
        trader_id: order.trader_id
      }
      |> Enum.filter(fn {_, v} -> v end)
      |> Enum.into(%{})

    case Repo.get(Order, data.order_id) do
      nil -> %Order{id: data.order_id}
      order -> order
    end
    |> Order.changeset(data)
    |> DataWarehouse.Repo.insert_or_update()

    {:noreply, state}
  end

  defp via_tuple(topic) do
    {:via, Registry, {:subscriber_workers, topic}}
  end
end
