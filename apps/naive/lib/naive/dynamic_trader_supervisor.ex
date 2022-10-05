defmodule Naive.DynamicTraderSupervisor do
  use DynamicSupervisor

  require Logger

  import Ecto.Query

  alias Naive.Schema.Traders

  alias Naive.Repo
  alias Naive.Schema.Traders
  alias Naive.Strategy
  alias Naive.Trader

  @registry :naive_traders

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def autostart_workers do
    Repo.all(
      from(t in Traders,
        where: t.status == "on",
        select: t.id
      )
    )
    |> Enum.map(&start_child/1)
  end

  def start_worker(id), do: start_child(id)

  def start_worker(symbol, strategy, interval, args) do
    Logger.info("Starting trading on #{symbol}")

    case get_trader(symbol, strategy, interval, args) do
      nil ->
        create_trader(symbol, strategy, interval, args)
        |> elem(1)
        |> start_worker()

      [_id, "on"] ->
        Logger.info("Worker already started")
        :error

      [id, "off"] ->
        id
        |> Ecto.UUID.load!()
        |> Strategy.update_status("on")
        |> elem(1)
        |> Map.get(:id)
        |> start_worker()
    end
  end

  def stop_worker(id), do: stop_child(id)

  def stop_worker(symbol, strategy, interval, args) do
    Logger.info("Stopping trading on #{symbol}")

    case get_trader(symbol, strategy, interval, args) do
      nil ->
        Logger.warn("No trader found", [symbol, strategy, interval, args])
        {:error, "No trader found"}

      [id, "on"] ->
        id
        |> Ecto.UUID.load!()
        |> Strategy.update_status("off")
        |> elem(1)
        |> Map.get(:id)
        |> stop_worker()

      [_id, "off"] ->
        Logger.info("Worker already off")
        {:error, "Worker already off"}
    end
  end

  def shutdown_worker(symbol, strategy, interval, args) when is_binary(symbol) do
    Logger.info("Shutdown of trading on #{symbol} initialized")
    {:ok, settings} = Strategy.update_status(symbol, "shutdown")
    Trader.notify(:settings_updated, settings)
    {:ok, settings}
  end

  defp start_child(id) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Trader, id}
    )
  end

  defp stop_child(args) do
    case Registry.lookup(@registry, args) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      _ -> Logger.warn("Unable to locate process assigned to #{inspect(args)}")
    end
  end

  defp get_trader(symbol, strategy, interval, args) do
    args = Poison.encode!(args)
    strategy = to_string(strategy)

    "traders"
    |> where([t], t.symbol == ^symbol)
    |> where([t], t.strategy == ^strategy)
    |> where([t], t.interval == ^interval)
    |> where([t], t.args == ^args)
    |> select([t], [t.id, t.status])
    |> Repo.one()
  end

  defp create_trader(symbol, strategy, interval, args) do
    args = Poison.encode!(args)
    strategy = to_string(strategy)

    trader = %Traders{
      symbol: symbol,
      strategy: strategy,
      args: args,
      interval: interval,
      status: "on"
    }

    case Repo.insert(trader) do
      {:ok, %{id: id}} ->
        {:ok, id}

      {:error, error} ->
        {:error, error}
    end
  end
end
