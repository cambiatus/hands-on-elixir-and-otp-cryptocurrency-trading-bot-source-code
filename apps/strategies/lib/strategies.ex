defmodule Strategies do
  @moduledoc """
  Documentation for `Strategies`.
  """


  @exchange_client Application.get_env(:strategies, :exchange_client)
  @logger Application.get_env(:core, :logger)

  alias Decimal, as: D

  require Logger
  require Poison

  @spec start_strategy(atom(), binary(), binary(), map()) :: {:ok, map} | {:error, any}
  def start_strategy(strategy, symbol, interval, args)

  def start_strategy(:sma, symbol, interval, %{"sma_s" => _sma_s, "sma_l" => sma_l}) do
    case @exchange_client.get_recent_klines_data(symbol, interval, sma_l) do
      {:ok, initial_data} ->
        {:ok, Map.put(initial_data, :complete, List.duplicate(true, sma_l))}

      {:error, error} ->
        Logger.info("Could not get historical data for #{symbol} at #{interval}")
        {:error, error}
      end
  end

  def start_strategy(strategy, _, _, _) do
    @logger.info("Invalid strategy: #{strategy}")
    {:error, "Invalid strategy"}
  end

  def execute_strategy(:sma, data, position, %{"sma_s" => sma_s, "sma_l" => sma_l}) do
    args = [parse_data(data), position, sma_s, sma_l]

    case Strategies.Caller.call_python(:sma, :execute_strategy, args) do
      {:ok, decision} ->
        decision = parse_decision(decision)
        {:ok, decision}

      response ->
        @logger.info(
          "Unexpected response from python strategy" <>
            "#{response}"
        )

        :error
    end
  end

  defp parse_data(data) do
    Poison.encode!(data)
  end

  defp parse_decision(decision) do
    decision_list =
      decision
      |> Enum.at(0)
      |> Enum.map(fn element ->
        cond do
          is_list(element) ->
            to_string(element)
          is_number(element) ->
            D.cast(element)
            |> elem(1)
        end
      end)

    position = Enum.at(decision, 1)

    [decision_list, position]
  end
end
