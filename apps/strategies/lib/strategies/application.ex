defmodule Strategies.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @python_workers Application.get_env(:strategies, :python_workers)
  @python_workers_overflow Application.get_env(:strategies, :python_worker_overflow)

  defp python_poolboy_config do
    [
      {:name, {:local, :worker}},
      {:worker_module, Strategies.PythonWorker},
      {:size, @python_workers},
      {:max_overflow, @python_workers_overflow}
    ]
  end

  @impl true
  def start(_type, _args) do
    children = [
      :poolboy.child_spec(:worker, python_poolboy_config())
      # Starts a worker by calling: Strategies.Worker.start_link(arg)
      # {Strategies.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Strategies.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
