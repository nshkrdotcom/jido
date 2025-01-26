defmodule Jido.Runner.SimpleTest do
  use ExUnit.Case, async: true
  alias Jido.Runner.Simple
  alias Jido.Error
  alias Jido.Instruction
  alias Jido.Agent.Directive.EnqueueDirective
  alias JidoTest.TestActions.{Add, ErrorAction, CompensateAction}
  alias JidoTest.TestAgents.FullFeaturedAgent

  @moduletag :capture_log

  describe "run/2" do
    test "executes single instruction successfully" do
      instruction = %Instruction{
        action: Add,
        params: %{value: 0, amount: 1},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, updated_agent} = Simple.run(agent)
      assert updated_agent.state.value == 1
      assert updated_agent.result == %{value: 1}
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "executes only first instruction with three in queue" do
      instruction1 = %Instruction{
        action: Add,
        params: %{value: 0, amount: 1},
        context: %{}
      }

      instruction2 = %Instruction{
        action: Add,
        params: %{value: 1, amount: 2},
        context: %{}
      }

      instruction3 = %Instruction{
        action: Add,
        params: %{value: 3, amount: 3},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")

      agent = %{
        agent
        | pending_instructions: :queue.from_list([instruction1, instruction2, instruction3])
      }

      assert {:ok, updated_agent} = Simple.run(agent)
      # First instruction executed
      assert updated_agent.state.value == 1
      assert updated_agent.result == %{value: 1}
      # Two instructions remain
      assert :queue.len(updated_agent.pending_instructions) == 2

      # Verify remaining instructions in order
      {{:value, next}, queue} = :queue.out(updated_agent.pending_instructions)
      assert next == instruction2

      {{:value, last}, _} = :queue.out(queue)
      assert last == instruction3
    end

    test "handles instruction execution error" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :validation},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Validation error"
    end

    test "returns unchanged agent when no pending instructions" do
      agent = FullFeaturedAgent.new("test-agent")
      assert {:ok, ^agent} = Simple.run(agent)
    end

    test "executes only first instruction and preserves remaining in queue" do
      instruction1 = %Instruction{
        action: Add,
        params: %{value: 0, amount: 1},
        context: %{}
      }

      instruction2 = %Instruction{
        action: Add,
        params: %{value: 1, amount: 1},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction1, instruction2])}

      assert {:ok, updated_agent} = Simple.run(agent)
      assert updated_agent.state.value == 1
      assert updated_agent.result == %{value: 1}
      assert :queue.len(updated_agent.pending_instructions) == 1

      # Verify remaining instruction
      {{:value, remaining}, _} = :queue.out(updated_agent.pending_instructions)
      assert remaining == instruction2
    end

    test "handles directive returned from action" do
      instruction = %Instruction{
        action: JidoTest.TestActions.EnqueueAction,
        params: %{
          action: :next_action,
          params: %{}
        },
        context: %{},
        opts: [timeout: 0]
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, updated_agent} = Simple.run(agent)
      assert updated_agent.result == %{}
      assert :queue.len(updated_agent.pending_instructions) == 1

      # Verify enqueued instruction
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :next_action
      assert enqueued.params == %{}
    end

    test "handles invalid directive returned from action" do
      instruction = %Instruction{
        action: JidoTest.TestActions.EnqueueAction,
        params: %{
          # Invalid - action is required
          action: nil,
          params: %{}
        },
        context: %{},
        opts: [timeout: 0]
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, :invalid_action} = Simple.run(agent)
    end

    test "does not apply state when apply_state is false" do
      instruction = %Instruction{
        action: Add,
        params: %{value: 0, amount: 1},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, updated_agent} = Simple.run(agent, apply_state: false)
      # State unchanged
      assert updated_agent.state.value == 0
      # Result still set
      assert updated_agent.result == %{value: 1}
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "handles multiple directives from action" do
      instruction = %Instruction{
        action: JidoTest.TestActions.MultiDirectiveAction,
        params: %{},
        context: %{},
        opts: [timeout: 0]
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, updated_agent} = Simple.run(agent)
      assert :queue.len(updated_agent.pending_instructions) == 2

      # Verify enqueued instructions
      {{:value, first}, queue} = :queue.out(updated_agent.pending_instructions)
      assert first.action == :action1
      assert first.params == %{}

      {{:value, second}, _} = :queue.out(queue)
      assert second.action == :action2
      assert second.params == %{}
    end

    test "handles runtime errors in action execution" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :runtime},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Server error in JidoTest.TestActions.ErrorAction: Runtime error"
    end

    test "handles argument errors in action execution" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :argument},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Argument error in JidoTest.TestActions.ErrorAction: Argument error"
    end

    test "handles compensation in action execution" do
      instruction = %Instruction{
        action: CompensateAction,
        params: %{
          should_fail: true,
          compensation_should_fail: false,
          test_value: "test"
        },
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Compensation completed for: Intentional failure"
    end

    test "preserves agent state on error" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :runtime},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")

      agent = %{
        agent
        | state: Map.put(agent.state, :value, 42),
          pending_instructions: :queue.from_list([instruction])
      }

      initial_state = agent.state

      assert {:error, _} = Simple.run(agent)
      assert agent.state == initial_state
    end

    test "handles custom errors in action execution" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :custom},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Server error in JidoTest.TestActions.ErrorAction: Custom error"
    end
  end
end
