defmodule Jido.Runner.ChainTest do
  use ExUnit.Case, async: true
  alias Jido.Runner.Chain
  alias Jido.Instruction
  alias JidoTest.TestActions.{Add, Multiply, ErrorAction, EnqueueAction, CompensateAction}
  alias JidoTest.TestAgents.FullFeaturedAgent

  @moduletag :capture_log

  describe "run/2" do
    test "executes instructions in sequence and returns final result" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 1},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 2, amount: 2},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert updated_agent.state.value == 4
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "executes all initial instructions but accumulates directive instructions in queue" do
      # Initial instructions: Add(0,1) -> EnqueueAction -> Add(1,2)
      # EnqueueAction will add a new instruction but it shouldn't be executed
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :next_action,
            params: %{value: 42}
          },
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 2},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      # Verify all initial instructions executed
      assert updated_agent.state.value == 3

      # Verify directive's instruction was enqueued but not executed
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :next_action
      assert enqueued.params == %{value: 42}
    end

    test "returns unchanged agent when no pending instructions" do
      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | result: :ok}
      assert {:ok, ^agent, []} = Chain.run(agent)
    end

    test "propagates errors from actions" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: ErrorAction,
          params: %{error_type: :validation},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 1},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message == "Validation error"
    end

    test "accumulates directives in queue from single action" do
      instructions = [
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :next_action,
            params: %{value: 1}
          },
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :next_action
      assert enqueued.params == %{value: 1}
    end

    test "accumulates multiple directives in queue from chain of actions" do
      instructions = [
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :first_action,
            params: %{value: 1}
          },
          context: %{}
        },
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :second_action,
            params: %{value: 2}
          },
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert :queue.len(updated_agent.pending_instructions) == 2

      # Verify enqueued instructions
      {{:value, first}, queue} = :queue.out(updated_agent.pending_instructions)
      assert first.action == :first_action
      assert first.params == %{value: 1}

      {{:value, second}, _} = :queue.out(queue)
      assert second.action == :second_action
      assert second.params == %{value: 2}
    end

    test "accumulates directives while executing state changes" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :next_action,
            params: %{value: 1}
          },
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      # State changes applied
      assert updated_agent.state.value == 1
      # Directive accumulated
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :next_action
      assert enqueued.params == %{value: 1}
    end

    test "accumulates results through Add, Multiply, Add chain" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 10, amount: 1},
          context: %{}
        },
        %Instruction{
          action: Multiply,
          params: %{value: 11, amount: 2},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 22, amount: 8},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")

      agent = %{
        agent
        | state: Map.put(agent.state, :value, 10),
          pending_instructions: :queue.from_list(instructions)
      }

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert updated_agent.state.value == 30
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "handles runtime errors in action execution" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: ErrorAction,
          params: %{error_type: :runtime},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message == "Server error in JidoTest.TestActions.ErrorAction: Runtime error"
    end

    test "handles argument errors in action execution" do
      instructions = [
        %Instruction{
          action: ErrorAction,
          params: %{error_type: :argument},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message == "Argument error in JidoTest.TestActions.ErrorAction: Argument error"
    end

    test "handles compensation in action execution" do
      instructions = [
        %Instruction{
          action: CompensateAction,
          params: %{
            should_fail: true,
            compensation_should_fail: false,
            test_value: "test"
          },
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message == "Compensation completed for: Intentional failure"
    end

    test "preserves agent state on error" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: ErrorAction,
          params: %{error_type: :runtime},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")

      agent = %{
        agent
        | state: Map.put(agent.state, :value, 42),
          pending_instructions: :queue.from_list(instructions)
      }

      initial_state = agent.state

      assert {:error, _} = Chain.run(agent)
      assert agent.state == initial_state
    end

    test "handles custom errors in action execution" do
      instructions = [
        %Instruction{
          action: ErrorAction,
          params: %{error_type: :custom},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message == "Server error in JidoTest.TestActions.ErrorAction: Custom error"
    end

    test "executes all instructions and accumulates directives" do
      instructions = [
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :first_action,
            params: %{value: 1}
          },
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      # Second instruction executed
      assert updated_agent.state.value == 1
      # Directive accumulated
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :first_action
      assert enqueued.params == %{value: 1}
    end
  end
end
