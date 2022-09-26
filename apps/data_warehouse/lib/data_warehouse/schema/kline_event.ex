defmodule DataWarehouse.Schema.KlineEvent do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "kline_events" do
    field(:event_type, :string)
    field(:event_time, :integer)
    field(:symbol, :string)
    field(:start_time, :integer)
    field(:close_time, :integer)
    field(:interval, :string)
    field(:first_trade_id, :integer)
    field(:last_trade_id, :integer)
    field(:open_price, :string)
    field(:close_price, :string)
    field(:high_price, :string)
    field(:low_price, :string)
    field(:base_asset_volume, :string)
    field(:number_of_trades, :integer)
    field(:complete, :boolean)
    field(:quote_asset_volume, :string)
    field(:taker_buy_base_asset_volume, :string)
    field(:taker_buy_quote_asset_volume, :string)

    timestamps()
  end
end
