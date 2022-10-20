defmodule Streamer do
  @moduledoc """
  Documentation for `Streamer`.
  """
  alias Streamer.DynamicStreamerSupervisor

  def start_streaming(symbol, interval) do
    symbol
    |> String.upcase()
    |> DynamicStreamerSupervisor.start_worker(interval)
  end

  def stop_streaming(symbol, interval) do
    symbol
    |> String.upcase()
    |> DynamicStreamerSupervisor.stop_worker(interval)
  end
end
