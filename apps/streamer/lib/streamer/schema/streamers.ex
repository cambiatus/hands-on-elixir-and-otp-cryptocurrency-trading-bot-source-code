defmodule Streamer.Schema.Streamers do
  use Ecto.Schema

  alias Streamer.Schema.{StreamingIntervalEnum, StreamingStatusEnum}

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "streamers" do
    field(:symbol, :string)
    field(:status, StreamingStatusEnum)
    field(:interval, StreamingIntervalEnum)

    timestamps()
  end
end
