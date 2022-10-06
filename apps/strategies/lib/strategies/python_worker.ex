defmodule Strategies.PythonWorker do
  @moduledoc false

  use GenServer

  require Logger

  @logger Application.compile_env(:core, :logger)

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  def init(_) do
    # Path where we store our python code
    path = Application.app_dir(:strategies, "priv/python")
    # Path to the virtual environment's interpreter that executes the code
    interpreter = [path, "/bin/python"] |> Path.join()

    # Start a process to monitor python
    case :python.start([{:python_path, to_charlist(path)}, {:python, to_charlist(interpreter)}]) do
      {:ok, pid} ->
        @logger.info("[#{__MODULE__}] Started python worker")
        {:ok, pid}

      {:error, error} ->
        {:stop, error}
    end
  end

  def handle_call(%{module: module, function: function, args: args}, _from, pid)
      when is_atom(module) and is_atom(function) and is_list(args) do
    try do
      result = :python.call(pid, module, function, args)
      {:reply, {:ok, result}, pid}
    catch
      {:python, class, argument, stack_trace} ->
        {:stop, [class, argument, stack_trace], {:error, "Error when executing python"}, pid}
    end
  end
end
