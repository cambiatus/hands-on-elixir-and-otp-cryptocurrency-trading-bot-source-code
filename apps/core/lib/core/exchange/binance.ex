defmodule Core.Exchange.Binance do
  @behaviour Core.Exchange

  alias Core.Exchange
  alias Binance.Futures
  alias Binance.{FuturesOrderResponse, FuturesOrder}

  @impl Core.Exchange
  def fetch_symbols() do
    case Futures.get_exchange_info() do
      {:ok, %{"symbols" => symbols}} ->
        symbols
        |> Enum.map(& &1["symbol"])
        |> then(&{:ok, &1})

      {:error, error} ->
        {:error, error}
    end
  end

  def fetch_exchange_info() do
    case Futures.get_exchange_info() do
      {:ok, %{"symbols" => symbols}} ->
        {:ok, %{symbols: symbols}}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Core.Exchange
  def get_order(symbol, _timestamp, order_id) do
    case Futures.get_order(symbol, order_id) do
      {:ok, order} ->
        {:ok,
         %Exchange.Order{
           id: order["orderId"],
           symbol: order["symbol"],
           price: order["price"],
           quantity: order["origQty"],
           side: side_to_atom(order["side"]),
           status: status_to_atom(order["status"]),
           timestamp: order["updateTime"]
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Core.Exchange
  def order_limit_buy(symbol, quantity, price) do
    case Futures.new_order(
           symbol,
           "BUY",
           "LIMIT",
           %{
             quantity: quantity,
             price: price,
             timeInForce: "GTC"
           }
         ) do
      {:ok, order} ->
        {:ok,
         %Exchange.Order{
           id: order["orderId"],
           price: order["price"],
           quantity: order["origQty"],
           side: :buy,
           status: :new,
           symbol: order["symbol"],
           timestamp: order["updateTime"]
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Core.Exchange
  def order_limit_sell(symbol, quantity, price) do
    case Futures.new_order(
           symbol,
           "SELL",
           "LIMIT",
           %{
             quantity: quantity,
             price: price,
             timeInForce: "GTC"
           }
         ) do
      {:ok, order} ->
        {:ok,
         %Exchange.Order{
           id: order["orderId"],
           price: order["price"],
           quantity: order["origQty"],
           side: :sell,
           status: :new,
           symbol: order["symbol"],
           timestamp: order["updateTime"]
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp side_to_atom("BUY"), do: :buy
  defp side_to_atom("SELL"), do: :sell

  defp status_to_atom("NEW"), do: :new
  defp status_to_atom("FILLED"), do: :filled
  defp status_to_atom("PARTIALLY_FILLED"), do: :partially_filled
  defp status_to_atom("CANCELLED"), do: :cancelled

  def create_listen_key() do
    case Futures.create_listen_key() do
      {:ok, %{"listenKey" => listen_key}} ->
        {:ok, %{listen_key: listen_key}}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Core.Exchange
  def fetch_symbol_filters(symbol) do
    case Futures.get_exchange_info() do
      {:ok, exchange_info} -> {:ok, fetch_symbol_filters(symbol, exchange_info)}
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_symbol_filters(symbol, exchange_info) do
    symbol_filters =
      exchange_info
      |> Map.get("symbols")
      |> Enum.find(&(&1["symbol"] == symbol))
      |> Map.get("filters")

    tick_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))
      |> Map.get("tickSize")

    step_size =
      symbol_filters
      |> Enum.find(&(&1["filterType"] == "LOT_SIZE"))
      |> Map.get("stepSize")

    %Exchange.SymbolInfo{
      symbol: symbol,
      tick_size: tick_size,
      step_size: step_size
    }
  end
end
