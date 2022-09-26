defmodule Core.Exchange.Binance do
  @behaviour Core.Exchange

  alias Core.Exchange
  alias Binance.Futures

  require Poison

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
    case Futures.new_order(%{
           symbol: symbol,
           side: "BUY",
           type: "LIMIT",
           quantity: quantity,
           price: price,
           timeInForce: "GTC"
         }) do
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
    case Futures.new_order(%{
           symbol: symbol,
           side: "SELL",
           type: "LIMIT",
           quantity: quantity,
           price: price,
           timeInForce: "GTC"
         }) do
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

  @doc """
  Use this function to get the `n` most recent entries in klines data, where n
  is defined by the datapoints argument.

  If you want to better define other parameters use get_klines/5 instead.
  """
  def get_recent_klines_data(symbol, interval, datapoints) do
    case Futures.get_server_time() do
      {:ok, %{"serverTime" => end_time}} ->
        start_time = end_time - datapoints * interval_to_miliseconds(interval)
        get_klines(symbol, interval, nil, start_time, end_time)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Use this function to get klines data with the specified paramenters.

  If you want to specify how many datapoints you wish to retrieve use get_recent_klines_data/3 instead.
  """
  def get_klines(symbol, interval, limit, start_time, end_time) do
    case Futures.get_klines(symbol, interval, limit, start_time, end_time) do
      {:ok, data} -> {:ok, decode_klines(data)}
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

  defp decode_klines(data) do
    pattern = %{
      start_time: [],
      open_price: [],
      high_price: [],
      low_price: [],
      close_price: [],
      volume: [],
      close_time: [],
      quote_asset_volume: [],
      number_of_trades: []
    }

    data
    |> Enum.reverse()
    |> Enum.reduce(pattern, fn entry, result ->
      %{
        start_time: [Enum.at(entry, 0) | result.start_time],
        open_price: [Enum.at(entry, 1) | result.open_price],
        high_price: [Enum.at(entry, 2) | result.high_price],
        low_price: [Enum.at(entry, 3) | result.low_price],
        close_price: [Enum.at(entry, 4) | result.close_price],
        volume: [Enum.at(entry, 5) | result.volume],
        close_time: [Enum.at(entry, 6) | result.close_time],
        quote_asset_volume: [Enum.at(entry, 7) | result.quote_asset_volume],
        number_of_trades: [Enum.at(entry, 8) | result.number_of_trades]
      }
    end)
  end

  defp interval_to_miliseconds(interval) do
    converter = %{
      "m" => 60,
      "h" => 60 * 60,
      "d" => 60 * 60 * 24,
      "w" => 60 * 60 * 24 * 7,
      "M" => 60 * 60 * 24 * 30
    }

    unit = String.at(interval, -1)
    time = interval |> String.replace(unit, "") |> String.to_integer()

    converter[unit] * time * 1000
  end
end
