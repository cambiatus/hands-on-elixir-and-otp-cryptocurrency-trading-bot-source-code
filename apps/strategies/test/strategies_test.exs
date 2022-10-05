defmodule StrategiesTest do
  use ExUnit.Case
  doctest Strategies

  test "greets the world" do
    assert Strategies.hello() == :world
  end
end
