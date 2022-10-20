defmodule Streamer.Repo.Migrations.CreateStreamersTable do
  use Ecto.Migration

  alias Streamer.Schema.{StreamingIntervalEnum, StreamingStatusEnum}

  def change do
    StreamingIntervalEnum.create_type()

    create table(:streamers, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:symbol, :text, null: false)
      add(:interval, StreamingIntervalEnum.type(), null: false)
      add(:status, StreamingStatusEnum.type(), default: "off", null: false)

      timestamps()
    end
  end
end
