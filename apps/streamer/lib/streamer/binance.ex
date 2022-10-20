defmodule Streamer.Binance do
  use WebSockex

  require Logger

  @exchange_client Application.get_env(:trader, :exchange_client)

  # @stream_endpoint "wss://stream.binance.com:9443/ws/"
  @stream_endpoint "wss://stream.binancefuture.com/ws/"

  def start_link(%{symbol: symbol, interval: interval}) do
    Logger.info(
      "Binance streamer is connecting to websocket " <>
        "stream for #{symbol} kline events with interval of #{interval}"
    )

    WebSockex.start_link(
      "#{@stream_endpoint}#{String.downcase(symbol)}@kline_#{interval}",
      __MODULE__,
      nil,
      name: via_tuple(symbol <> interval)
    )

    # TODO: Either move this data streamer to another start link
    #       OR conditionally start streaming if no user stream has been started
    # The way it is now it tries to start a stream whenever a streamer is initiated

    with [] <- Registry.lookup(:binance_streamers, "orders"),
         {:ok, %{listen_key: listen_key}} <- @exchange_client.create_listen_key() do
      WebSockex.start_link(
        "#{@stream_endpoint}#{listen_key}",
        __MODULE__,
        nil,
        name: via_tuple("orders")
      )
    else
      [{pid, _}] ->
        Logger.debug("Order stream already started by process #{pid}")
        {:ok, pid}

      {:error, error} ->
        Logger.info("Could not connect to user stream.")
        {:error, error}
    end
  end

  def handle_frame({_type, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} -> process_event(event)
      {:error, _} -> Logger.error("Unable to parse msg: #{msg}")
    end

    {:ok, state}
  end

  defp process_event(%{"e" => "trade"} = event) do
    trade_event = %Core.Struct.TradeEvent{
      :event_type => event["e"],
      :event_time => event["E"],
      :symbol => event["s"],
      :trade_id => event["t"],
      :price => event["p"],
      :quantity => event["q"],
      :buyer_order_id => event["b"],
      :seller_order_id => event["a"],
      :trade_time => event["T"],
      :buyer_market_maker => event["m"]
    }

    Logger.debug(
      "Trade event received " <>
        "#{trade_event.symbol}@#{trade_event.price}"
    )

    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "TRADE_EVENTS:#{trade_event.symbol}",
      trade_event
    )
  end

  defp process_event(%{"e" => "kline", "k" => kline} = event) do
    kline_event = %Core.Struct.KlineEvent{
      :event_type => event["e"],
      :event_time => event["E"],
      :symbol => event["s"],
      :start_time => kline["t"],
      :close_time => kline["T"],
      :interval => kline["i"],
      :first_trade_id => kline["f"],
      :last_trade_id => kline["L"],
      :open_price => kline["o"],
      :close_price => kline["c"],
      :high_price => kline["h"],
      :low_price => kline["l"],
      :base_asset_volume => kline["v"],
      :number_of_trades => kline["n"],
      :complete => kline["x"],
      :quote_asset_volume => kline["q"],
      :taker_buy_base_asset_volume => kline["V"],
      :taker_buy_quote_asset_volume => kline["Q"]
    }

    Logger.debug(
      "Kline event received " <>
        "#{kline_event.symbol}@#{kline_event.close_price}"
    )

    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "KLINE_EVENTS:#{kline_event.symbol}#{kline_event.interval}",
      kline_event
    )
  end

  defp process_event(%{"e" => "ORDER_TRADE_UPDATE", "o" => order} = event) do
    order_event = %Core.Struct.OrderEvent{
      :event_type => event["e"],
      :event_time => event["E"],
      :transaction_time => event["T"],
      :symbol => order["s"],
      :client_order_id => order["c"],
      :side => order["S"],
      :order_type => order["o"],
      :time_in_force => order["f"],
      :original_quantity => order["q"],
      :original_price => order["p"],
      :average_price => order["ap"],
      # Please ignore with TRAILING_STOP_MARKET order
      :stop_price => order["sp"],
      :execution_type => order["x"],
      :order_status => order["X"],
      :order_id => order["i"],
      :order_last_filled_quantity => order["l"],
      :order_filled_accumulated_quantity => order["z"],
      :last_filled_price => order["L"],
      # will not push if no commission
      :commission_asset => order["N"],
      # will not push if no commission
      :commission => order["n"],
      :order_trade_time => order["T"],
      :trade_id => order["t"],
      :bids_notional => order["b"],
      :ask_notional => order["a"],
      :is_this_trade_the_maker_side? => order["m"],
      :is_this_reduce_only => order["R"],
      :stop_price_working_type => order["wt"],
      :original_order_type => order["ot"],
      :position_side => order["ps"],
      # pushed with conditional order
      :if_close_all => order["cp"],
      # only pushed with TRAILING_STOP_MARKET order
      :activation_price => order["AP"],
      # only pushed with TRAILING_STOP_MARKET order
      :callback_rate => order["cr"],
      :realized_profitofthetrade => order["rp"]
    }

    Logger.debug(
      "Order event received " <>
        "#{order_event.symbol}@#{order_event.original_price}" <>
        " Status: #{order_event.order_status}"
    )

    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "ORDER_EVENTS:#{order_event.symbol}",
      order_event
    )
  end

  defp process_event(event) do
    Logger.debug("Ignored event of type #{event["e"]}")
  end

  defp via_tuple(name) do
    {:via, Registry, {:binance_streamers, name}}
  end
end
