defmodule DataWarehouse.Schema.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}

  schema "orders" do
    field(:symbol, :string)
    field(:price, :string)
    field(:quantity, :string)
    field(:side, :string)
    field(:status, :string)
    field(:type, :string)
    field(:time_in_force, :string)
    field(:average_price, :string)
    field(:order_id, :integer)
    field(:realized_quantity, :string)
    field(:position_side, :string)
    field(:timestamp, :integer)
    field(:trader_id, :binary_id)

    timestamps()
  end

  @required_fields ~w(id status symbol)a
  @optional_fields ~w(price quantity side type time_in_force average_price order_id
                      realized_quantity position_side timestamp trader_id)a

  def changeset(order, params \\ %{}) do
    order
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:id)
  end
end
