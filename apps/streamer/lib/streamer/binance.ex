defmodule Streamer.Binance do
  use WebSockex

  require Logger

  # @stream_endpoint "wss://stream.binance.com:9443/ws/"
  @stream_endpoint "wss://stream.binancefuture.com/ws/"

  def start_link(symbol) do
    Logger.info(
      "Binance streamer is connecting to websocket " <>
        "stream for #{symbol} trade events"
    )

    WebSockex.start_link(
      "#{@stream_endpoint}#{String.downcase(symbol)}@trade",
      __MODULE__,
      nil,
      name: via_tuple(symbol)
    )

    # TODO: Either move this data streamer to another star link
    #       OR conditionally start streaming if no user stream has been started
    # The way it is now it tries to start a stream whenever a streamer is initiated

    {:ok, %Binance.DataStream{listen_key: listen_key}} = Binance.create_listen_key()

    WebSockex.start_link(
      "#{@stream_endpoint}#{listen_key}",
      __MODULE__,
      nil,
      name: {:via, Registry, {:binance_streamers, "orders"}}
    )
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

    Logger.info(
      "Order event received " <>
        "#{order_event.symbol}@#{order_event.original_price}" <>
        " Status: #{order_event.order_status}"
    )

    Phoenix.PubSub.broadcast(
      Core.PubSub,
      "TRADE_EVENTS:#{order_event.symbol}",
      order_event
    )
  end

  defp process_event(event) do
    Logger.info("Ignored event of type #{event["e"]}")
  end

  defp via_tuple(symbol) do
    {:via, Registry, {:binance_streamers, symbol}}
  end
end
