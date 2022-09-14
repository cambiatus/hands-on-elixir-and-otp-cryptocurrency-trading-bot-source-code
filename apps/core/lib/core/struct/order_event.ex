defmodule Core.Struct.OrderEvent do
  defstruct [
    :event_type,
    :event_time,
    :transaction_time,
    :symbol,
    :client_order_id,
    :side,
    :order_type,
    :time_in_force,
    :original_quantity,
    :original_price,
    :average_price,
    # Please ignore with TRAILING_STOP_MARKET order
    :stop_price,
    :execution_type,
    :order_status,
    :order_id,
    :order_last_filled_quantity,
    :order_filled_accumulated_quantity,
    :last_filled_price,
    # will not push if no commission
    :commission_asset,
    # will not push if no commission
    :commission,
    :order_trade_time,
    :trade_id,
    :bids_notional,
    :ask_notional,
    :is_this_trade_the_maker_side?,
    :is_this_reduce_only,
    :stop_price_working_type,
    :original_order_type,
    :position_side,
    # pushed with conditional order
    :if_close_all,
    # only pushed with TRAILING_STOP_MARKET order
    :activation_price,
    # only pushed with TRAILING_STOP_MARKET order
    :callback_rate,
    :realized_profitofthetrade
  ]
end
