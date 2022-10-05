defmodule DataWarehouse.Repo.Migrations.AddedTraderColumnToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add(:order_id, :bigint)
      add(:average_price, :text)
      add(:type, :text)
      add(:time_in_force, :text)
      add(:realized_quantity, :text)
      add(:position_side, :text)
      add(:trader_id, :binary_id)
    end
  end
end
