defmodule JidoTest.Agent.Runtime.SignalTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  alias Jido.Signal

  describe "action_to_signal/4" do
    test "converts single atom action" do
      signal = RuntimeSignal.action_to_signal("agent-123", :test_action)
      action_type = RuntimeSignal.agent_cmd()

      assert %Signal{
               type: ^action_type,
               source: "/agent/agent-123",
               data: %{},
               extensions: %{
                 "actions" => [{:test_action, %{}}],
                 "apply_state" => true
               }
             } = signal
    end

    test "converts action tuple with args" do
      action = {:test_action, %{arg1: "value1"}}
      signal = RuntimeSignal.action_to_signal("agent-123", action)
      action_type = RuntimeSignal.agent_cmd()

      assert %Signal{
               type: ^action_type,
               extensions: %{
                 "actions" => [{:test_action, %{arg1: "value1"}}]
               }
             } = signal
    end

    test "converts list of actions" do
      actions = [
        {:action1, %{arg1: "val1"}},
        {:action2, %{arg2: "val2"}}
      ]

      signal = RuntimeSignal.action_to_signal("agent-123", actions)
      action_type = RuntimeSignal.agent_cmd()

      assert %Signal{
               type: ^action_type,
               extensions: %{
                 "actions" => [
                   {:action1, %{arg1: "val1"}},
                   {:action2, %{arg2: "val2"}}
                 ]
               }
             } = signal
    end

    test "accepts custom args" do
      args = %{custom: "value"}
      signal = RuntimeSignal.action_to_signal("agent-123", :test, args)
      action_type = RuntimeSignal.agent_cmd()

      assert %Signal{
               type: ^action_type,
               data: ^args
             } = signal
    end

    test "accepts apply_state option" do
      signal = RuntimeSignal.action_to_signal("agent-123", :test, %{}, apply_state: false)
      action_type = RuntimeSignal.agent_cmd()

      assert %Signal{
               type: ^action_type,
               extensions: %{
                 "apply_state" => false
               }
             } = signal
    end
  end

  describe "signal_to_action/1" do
    test "converts valid signal back to action tuple" do
      action_type = RuntimeSignal.agent_cmd()

      signal = %Signal{
        id: "test-123",
        type: action_type,
        source: "/agent/agent-123",
        data: %{arg: "value"},
        extensions: %{
          "actions" => [{:test_action, %{param: "value"}}],
          "apply_state" => true
        }
      }

      assert {
               [{:test_action, %{param: "value"}}],
               %{arg: "value"},
               [apply_state: true]
             } = RuntimeSignal.signal_to_action(signal)
    end

    test "handles multiple actions in signal" do
      action_type = RuntimeSignal.agent_cmd()

      signal = %Signal{
        id: "test-456",
        extensions: %{
          "actions" => [
            {:action1, %{p1: "v1"}},
            {:action2, %{p2: "v2"}}
          ],
          "apply_state" => true
        },
        data: %{},
        type: action_type,
        source: "/agent/agent-123"
      }

      assert {actions, _, _} = RuntimeSignal.signal_to_action(signal)
      assert length(actions) == 2
    end

    test "returns error for invalid signal format" do
      action_type = RuntimeSignal.agent_cmd()

      invalid_signal = %Signal{
        id: "test-789",
        extensions: %{},
        data: %{},
        type: action_type,
        source: "/agent/agent-123"
      }

      assert {:error, :invalid_signal_format} = RuntimeSignal.signal_to_action(invalid_signal)
    end

    test "returns error if apply_state is missing" do
      action_type = RuntimeSignal.agent_cmd()

      signal = %Signal{
        id: "test-101",
        extensions: %{
          "actions" => [{:test, %{}}]
        },
        type: action_type,
        source: "/agent/agent-123",
        data: %{}
      }

      assert {:error, :invalid_signal_format} = RuntimeSignal.signal_to_action(signal)
    end
  end
end
