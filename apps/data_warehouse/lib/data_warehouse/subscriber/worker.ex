defmodule DataWarehouse.Subscriber.Worker do
  use GenServer

  alias Core.Exchange
  alias Core.Struct.OrderEvent

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

  def handle_info(%Core.Struct.TradeEvent{} = trade_event, state) do
    opts =
      trade_event
      |> Map.from_struct()

    struct!(DataWarehouse.Schema.TradeEvent, opts)
    |> DataWarehouse.Repo.insert()

    {:noreply, state}
  end

  def handle_info(%OrderEvent{} = order, state) do
    data = %{
      id: order.order_id,
      symbol: order.symbol,
      price: order.original_price,
      quantity: order.original_quantity,
      side: order.side,
      status: order.order_status,
      timestamp: order.event_time
    }

    struct(DataWarehouse.Schema.Order, data)
    |> DataWarehouse.Repo.insert(
      on_conflict: :replace_all,
      conflict_target: :id
    )

    {:noreply, state}
  end

  def handle_info(%Exchange.Order{} = order, state) do
    data =
      order
      |> Map.from_struct()
      |> Map.merge(%{
        side: atom_to_side(order.side),
        status: atom_to_status(order.status)
      })

    struct(DataWarehouse.Schema.Order, data)
    |> DataWarehouse.Repo.insert(
      on_conflict: :replace_all,
      conflict_target: :id
    )

    {:noreply, state}
  end

  defp via_tuple(topic) do
    {:via, Registry, {:subscriber_workers, topic}}
  end

  defp atom_to_side(:buy), do: "BUY"
  defp atom_to_side(:sell), do: "SELL"

  defp atom_to_status(:new), do: "NEW"
  defp atom_to_status(:filled), do: "FILLED"
  defp atom_to_status(:partially_filled), do: "PARTIALLY_FILLED"
end
