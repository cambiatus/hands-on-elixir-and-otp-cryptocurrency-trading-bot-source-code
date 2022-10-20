defmodule Trader do
  @moduledoc """
  Documentation for `Trader`.
  """

  alias Trader.DynamicTraderSupervisor
  alias Trader.Worker

  def start_trading(symbol, strategy, interval, args) do
    symbol
    |> String.upcase()
    |> DynamicTraderSupervisor.start_worker(strategy, interval, args)
  end

  def stop_trading(symbol, strategy, interval, args) do
    symbol
    |> String.upcase()
    |> DynamicTraderSupervisor.stop_worker(strategy, interval, args)
  end

  def shutdown_trading(symbol, strategy, interval, args) do
    symbol
    |> String.upcase()
    |> DynamicTraderSupervisor.shutdown_worker(strategy, interval, args)
  end

  def get_positions(symbol, strategy, interval, args) do
    symbol
    |> String.upcase()
    |> Trader.get_positions(strategy, interval, args)
  end
end
