defmodule Jido.Runner.ChainTest do
  use ExUnit.Case, async: true
  alias Jido.Runner.Chain
  alias Jido.Error
  alias JidoTest.TestActions.{Add, ErrorAction}

  @moduletag :capture_log

  describe "run/3" do
    test "executes actions in sequence and returns final state" do
      agent = %{id: "test-agent", state: %{value: 0}}

      # Each Add action operates on the result of the previous one
      actions = [
        # 0 -> 1
        {Add, [value: 1]},
        # 1 -> 2
        {Add, [value: 1, amount: 1]},
        # 2 -> 4
        {Add, [value: 2, amount: 2]}
      ]

      assert {:ok, %{state: %{value: 4}}} = Chain.run(agent, actions)
    end

    test "handles empty action list" do
      agent = %{id: "test-agent", state: %{value: 123}}
      assert {:ok, %{state: %{value: 123}}} = Chain.run(agent, [])
    end

    test "propagates errors from actions" do
      agent = %{id: "test-agent", state: %{}}

      actions = [
        {Add, [value: 1]},
        {ErrorAction, [error_type: :validation]},
        {Add, [value: 1]}
      ]

      assert {:error, %Error{type: :execution_error}} = Chain.run(agent, actions)
    end

    test "handles invalid action tuples" do
      agent = %{id: "test-agent", state: %{}}
      actions = [{InvalidModule, []}]

      assert {:error, %Error{type: :invalid_action}} = Chain.run(agent, actions)
    end
  end
end
