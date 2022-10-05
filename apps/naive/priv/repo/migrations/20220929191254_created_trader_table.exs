defmodule Naive.Repo.Migrations.CreateTraders do
  use Ecto.Migration

  alias Naive.Schema.{TradingIntervalEnum, TradingStatusEnum}

  def change do
    TradingIntervalEnum.create_type()

    create table(:traders, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:symbol, :text, null: false)
      add(:strategy, :text, null: false)
      add(:args, :text, null: false)
      add(:interval, TradingIntervalEnum.type(), null: false)
      add(:status, TradingStatusEnum.type(), default: "off", null: false)

      timestamps()
    end
  end
end
