defmodule Core.Struct.KlineEvent do
  defstruct [
    :event_type,
    :event_time,
    :symbol,
    :start_time,
    :close_time,
    :interval,
    :first_trade_id,
    :last_trade_id,
    :open_price,
    :close_price,
    :high_price,
    :low_price,
    :base_asset_volume,
    :number_of_trades,
    :complete,
    :quote_asset_volume,
    :taker_buy_base_asset_volume,
    :taker_buy_quote_asset_volume
  ]
end
