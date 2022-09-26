defmodule DataWarehouse.Repo.Migrations.CreateKlineEvents do
  use Ecto.Migration

  def change do
    create table(:kline_events, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:event_type, :text)
      add(:event_time, :bigint)
      add(:symbol, :text)
      add(:start_time, :bigint)
      add(:close_time, :bigint)
      add(:interval, :text)
      add(:first_trade_id, :integer)
      add(:last_trade_id, :integer)
      add(:open_price, :text)
      add(:close_price, :text)
      add(:high_price, :text)
      add(:low_price, :text)
      add(:base_asset_volume, :text)
      add(:number_of_trades, :int)
      add(:complete, :bool)
      add(:quote_asset_volume, :text)
      add(:taker_buy_base_asset_volume, :text)
      add(:taker_buy_quote_asset_volume, :text)

      timestamps()
    end
  end
end
