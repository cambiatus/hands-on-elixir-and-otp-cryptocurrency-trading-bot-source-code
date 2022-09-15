defmodule Strategies.Caller do
  @timeout 60000

  def call_python(module, function, args) do
    Task.async(fn ->
      :poolboy.transaction(
        :worker,
        fn pid -> GenServer.call(pid, %{module: module, function: function, args: args}) end,
        @timeout
      )
    end)
    |> Task.await(@timeout)
  end
end
