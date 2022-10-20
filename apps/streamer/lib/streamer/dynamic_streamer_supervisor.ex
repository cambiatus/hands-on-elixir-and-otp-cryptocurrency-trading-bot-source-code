defmodule Streamer.DynamicStreamerSupervisor do
  use DynamicSupervisor

  require Logger

  alias Streamer.Binance
  alias Streamer.Repo
  alias Streamer.Schema.Streamers

  import Ecto.Query, only: [from: 2]

  @registry :binance_streamers

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def autostart_workers do
    Repo.all(
      from(s in Streamers,
        where: s.status == "on",
        select: [s.symbol, s.interval]
      )
    )
    |> Enum.map(fn [symbol, interval] -> start_child(symbol, to_string(interval)) end)
  end

  def start_worker(symbol, interval) do
    Logger.info("Starting streaming #{symbol} trade events")
    update_status(symbol, interval, "on")
    start_child(symbol, interval)
  end

  def stop_worker(symbol, interval) do
    Logger.info("Stopping streaming #{symbol} trade events")
    update_status(symbol, interval, "off")
    stop_child(symbol, interval)
  end

  defp update_status(symbol, interval, status)
       when is_binary(symbol) and is_binary(status) do
    case Repo.get_by(Streamers, symbol: symbol, interval: interval) do
      nil ->
        %Streamers{
          symbol: symbol,
          interval: interval,
          status: status
        }
        |> Repo.insert()

      streamer ->
        streamer
        |> Ecto.Changeset.change(%{status: status})
        |> Repo.update()
    end
  end

  defp start_child(symbol, interval) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Binance, %{symbol: symbol, interval: interval}}
    )
  end

  defp stop_child(symbol, interval) do
    case Registry.lookup(@registry, %{symbol: symbol, interval: interval}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      _ ->
        Logger.warn(
          "Unable to locate process assigned to #{inspect(%{symbol: symbol, interval: interval})}"
        )
    end
  end
end
