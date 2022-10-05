defmodule Naive.Schema.Traders do
  use Ecto.Schema

  alias Naive.Schema.{TradingIntervalEnum, TradingStatusEnum}

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "traders" do
    field(:symbol, :string)
    field(:strategy, :string)
    field(:args, :string)
    field(:interval, TradingIntervalEnum)
    field(:status, TradingStatusEnum)

    timestamps()
  end
end
