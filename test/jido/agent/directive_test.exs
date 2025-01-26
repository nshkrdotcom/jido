defmodule JidoTest.DirectiveTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.Agent.Directive

  alias Jido.Agent.Directive.{
    EnqueueDirective,
    RegisterActionDirective,
    DeregisterActionDirective,
    SpawnDirective,
    KillDirective,
    PublishDirective,
    SubscribeDirective,
    UnsubscribeDirective
  }

  alias Jido.Instruction
  alias JidoTest.TestAgents.FullFeaturedAgent
  alias JidoTest.TestActions.{Add, ErrorAction}

  setup :verify_on_exit!

  describe "is_directive?/1" do
    test "returns true for valid directives" do
      assert Directive.is_directive?(%EnqueueDirective{action: :test})
      assert Directive.is_directive?(%RegisterActionDirective{action_module: TestModule})
      assert Directive.is_directive?(%DeregisterActionDirective{action_module: TestModule})
    end

    test "returns true for ok-tupled directives" do
      assert Directive.is_directive?({:ok, %EnqueueDirective{action: :test}})
      assert Directive.is_directive?({:ok, %RegisterActionDirective{action_module: TestModule}})
      assert Directive.is_directive?({:ok, %DeregisterActionDirective{action_module: TestModule}})
    end

    test "returns false for non-directives" do
      refute Directive.is_directive?(%{action: :test})
      refute Directive.is_directive?({:error, %EnqueueDirective{action: :test}})
      refute Directive.is_directive?(nil)
      refute Directive.is_directive?(:not_a_directive)
    end
  end

  describe "validate_directives/1" do
    test "validates single valid directive" do
      assert :ok = Directive.validate_directives(%EnqueueDirective{action: :test})

      assert :ok =
               Directive.validate_directives(%RegisterActionDirective{action_module: TestModule})

      assert :ok =
               Directive.validate_directives(%DeregisterActionDirective{
                 action_module: TestModule
               })
    end

    test "validates list of valid directives" do
      directives = [
        %EnqueueDirective{action: :test},
        %RegisterActionDirective{action_module: TestModule},
        %DeregisterActionDirective{action_module: TestModule}
      ]

      assert :ok = Directive.validate_directives(directives)
    end

    test "returns error for invalid single directive" do
      assert {:error, :invalid_action} =
               Directive.validate_directives(%EnqueueDirective{action: nil})

      assert {:error, :invalid_action_module} =
               Directive.validate_directives(%RegisterActionDirective{action_module: nil})

      assert {:error, :invalid_directive} = Directive.validate_directives(:not_a_directive)
    end

    test "returns error for list with any invalid directive" do
      directives = [
        %EnqueueDirective{action: :test},
        %EnqueueDirective{action: nil},
        %RegisterActionDirective{action_module: TestModule}
      ]

      assert {:error, :invalid_action} = Directive.validate_directives(directives)
    end

    test "validates system directives" do
      assert :ok = Directive.validate_directives(%SpawnDirective{module: TestModule, args: []})
      assert :ok = Directive.validate_directives(%KillDirective{pid: self()})

      assert :ok =
               Directive.validate_directives(%PublishDirective{stream_id: "test", signal: :test})

      assert :ok = Directive.validate_directives(%SubscribeDirective{stream_id: "test"})
      assert :ok = Directive.validate_directives(%UnsubscribeDirective{stream_id: "test"})
    end

    test "returns error for invalid system directives" do
      assert {:error, :invalid_module} =
               Directive.validate_directives(%SpawnDirective{module: nil, args: []})

      assert {:error, :invalid_pid} = Directive.validate_directives(%KillDirective{pid: nil})

      assert {:error, :invalid_stream_id} =
               Directive.validate_directives(%PublishDirective{stream_id: nil, signal: :test})

      assert {:error, :invalid_stream_id} =
               Directive.validate_directives(%SubscribeDirective{stream_id: nil})

      assert {:error, :invalid_stream_id} =
               Directive.validate_directives(%UnsubscribeDirective{stream_id: nil})
    end
  end

  describe "apply_directives/3 queue management" do
    setup do
      agent = FullFeaturedAgent.new("test-agent")
      {:ok, agent: agent}
    end

    test "appends new instructions to existing queue", %{agent: agent} do
      # First add an instruction to the queue
      initial_instruction = %Instruction{
        action: EnqueueAction,
        params: %{value: 1, amount: 5}
      }

      agent = %{agent | pending_instructions: :queue.from_list([initial_instruction])}

      # Create directive that should be appended to existing queue
      directive = %EnqueueDirective{
        action: Add,
        params: %{value: 1, amount: 5}
      }

      {:ok, updated_agent} = Directive.apply_directives(agent, directive)

      # Verify queue state - should have both instructions
      assert :queue.len(updated_agent.pending_instructions) == 2
      {{:value, first}, remaining} = :queue.out(updated_agent.pending_instructions)
      {{:value, second}, _} = :queue.out(remaining)

      # First instruction should be the original one
      assert first.action == EnqueueAction
      assert first.params == %{value: 1, amount: 5}

      # Second instruction should be the new one
      assert second.action == Add
      assert second.params == %{value: 1, amount: 5}
    end

    test "handles empty queue when applying directives", %{agent: agent} do
      directive = %EnqueueDirective{
        action: Add,
        params: %{value: 1}
      }

      {:ok, updated_agent} = Directive.apply_directives(agent, directive)

      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == Add
      assert instruction.params == %{value: 1}
    end

    test "maintains queue order when applying multiple directives", %{agent: agent} do
      directives = [
        %EnqueueDirective{action: Add, params: %{value: 1}},
        %EnqueueDirective{action: Add, params: %{value: 2}},
        %EnqueueDirective{action: Add, params: %{value: 3}}
      ]

      {:ok, updated_agent} = Directive.apply_directives(agent, directives)

      assert :queue.len(updated_agent.pending_instructions) == 3

      # Check order of instructions
      {{:value, first}, q1} = :queue.out(updated_agent.pending_instructions)
      {{:value, second}, q2} = :queue.out(q1)
      {{:value, third}, _} = :queue.out(q2)

      assert first.params.value == 1
      assert second.params.value == 2
      assert third.params.value == 3
    end

    test "handles complex queue transitions", %{agent: agent} do
      # Setup initial state with an EnqueueAction instruction
      initial_instruction = %Instruction{
        action: EnqueueAction,
        params: %{
          action: Add,
          params: %{value: 1, amount: 5}
        }
      }

      agent = %{agent | pending_instructions: :queue.from_list([initial_instruction])}

      # Apply multiple directives
      directives = [
        %EnqueueDirective{action: Add, params: %{value: 2}},
        %EnqueueDirective{action: Add, params: %{value: 3}}
      ]

      {:ok, updated_agent} = Directive.apply_directives(agent, directives)

      # Verify final queue state - should have all instructions
      assert :queue.len(updated_agent.pending_instructions) == 3

      {{:value, first}, q1} = :queue.out(updated_agent.pending_instructions)
      {{:value, second}, q2} = :queue.out(q1)
      {{:value, third}, _} = :queue.out(q2)

      # First should be original instruction
      assert first.action == EnqueueAction
      assert first.params.action == Add
      assert first.params.params.value == 1

      # Then the new ones in order
      assert second.action == Add
      assert second.params.value == 2
      assert third.action == Add
      assert third.params.value == 3
    end

    test "preserves queue on directive failure", %{agent: agent} do
      # Add initial instruction
      initial_instruction = %Instruction{
        action: Add,
        params: %{value: 1}
      }

      agent = %{agent | pending_instructions: :queue.from_list([initial_instruction])}

      # Try to apply invalid directive
      bad_directive = %EnqueueDirective{action: nil}

      {:error, :invalid_action} = Directive.apply_directives(agent, bad_directive)

      # Verify original instruction is still in queue
      assert :queue.len(agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(agent.pending_instructions)
      assert instruction.action == Add
      assert instruction.params.value == 1
    end
  end

  describe "apply_directives/3 edge cases" do
    setup do
      agent = FullFeaturedAgent.new("test-agent")
      {:ok, agent: agent}
    end

    test "handles multiple queued instructions with directive application", %{agent: agent} do
      # Setup multiple initial instructions
      initial_instructions = [
        %Instruction{action: EnqueueAction, params: %{action: Add, value: 1}},
        %Instruction{action: EnqueueAction, params: %{action: Add, value: 2}}
      ]

      agent = %{agent | pending_instructions: :queue.from_list(initial_instructions)}

      directive = %EnqueueDirective{action: Add, params: %{value: 3}}

      {:ok, updated_agent} = Directive.apply_directives(agent, directive)

      # Should have all three instructions
      assert :queue.len(updated_agent.pending_instructions) == 3
      {{:value, first}, q1} = :queue.out(updated_agent.pending_instructions)
      {{:value, second}, q2} = :queue.out(q1)
      {{:value, third}, _} = :queue.out(q2)

      # First two should be the original instructions
      assert first.action == EnqueueAction
      assert first.params.value == 1
      assert second.action == EnqueueAction
      assert second.params.value == 2

      # Last should be the new directive
      assert third.action == Add
      assert third.params.value == 3
    end

    test "handles partial directive application failure", %{agent: agent} do
      directives = [
        %EnqueueDirective{action: Add, params: %{value: 1}},
        # This will fail
        %EnqueueDirective{action: nil},
        %EnqueueDirective{action: Add, params: %{value: 2}}
      ]

      {:error, :invalid_action} = Directive.apply_directives(agent, directives)

      # Queue should be empty since we rollback on failure
      assert :queue.is_empty(agent.pending_instructions)
    end

    test "handles recursive directive application", %{agent: agent} do
      # Create a directive that will trigger another directive
      nested_directive = %EnqueueDirective{
        action: EnqueueAction,
        params: %{
          action: EnqueueAction,
          params: %{
            action: Add,
            params: %{value: 1}
          }
        }
      }

      {:ok, updated_agent} = Directive.apply_directives(agent, nested_directive)

      # Verify the nested structure is maintained
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == EnqueueAction
      assert instruction.params.action == EnqueueAction
      assert instruction.params.params.action == Add
    end

    test "handles max queue size limits", %{agent: agent} do
      # Create more directives than a reasonable queue should handle
      large_directive_list =
        Enum.map(1..1000, fn i ->
          %EnqueueDirective{action: Add, params: %{value: i}}
        end)

      {:ok, updated_agent} = Directive.apply_directives(agent, large_directive_list)

      # Verify queue integrity with large number of instructions
      assert :queue.len(updated_agent.pending_instructions) == 1000
      {{:value, first}, _} = :queue.out(updated_agent.pending_instructions)
      assert first.action == Add
      assert first.params.value == 1
    end

    test "handles invalid queue states", %{agent: agent} do
      # Simulate corrupted queue state
      corrupted_agent = %{agent | pending_instructions: :not_a_queue}

      directive = %EnqueueDirective{action: Add, params: %{value: 1}}

      assert_raise ArgumentError, fn ->
        Directive.apply_directives(corrupted_agent, directive)
      end
    end

    test "handles mixed directive types with queue operations", %{agent: agent} do
      # Mix different types of directives that affect the queue differently
      directives = [
        %RegisterActionDirective{action_module: Add},
        %EnqueueDirective{action: Add, params: %{value: 1}},
        %DeregisterActionDirective{action_module: Add}
      ]

      {:ok, updated_agent} = Directive.apply_directives(agent, directives)

      # Verify final state
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == Add
      assert instruction.params.value == 1
      # Should be deregistered
      refute Add in updated_agent.actions
    end

    test "handles empty directive list with existing queue", %{agent: agent} do
      # Setup initial queue state
      initial_instruction = %Instruction{action: Add, params: %{value: 1}}
      agent = %{agent | pending_instructions: :queue.from_list([initial_instruction])}

      # Apply empty directive list
      {:ok, updated_agent} = Directive.apply_directives(agent, [])

      # Should maintain existing queue state
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == Add
      assert instruction.params.value == 1
    end

    test "handles directive application with dirty state", %{agent: agent} do
      # Set dirty state flag
      agent = %{agent | dirty_state?: true}

      directive = %EnqueueDirective{action: Add, params: %{value: 1}}

      {:ok, updated_agent} = Directive.apply_directives(agent, directive)

      # Verify dirty state is preserved
      assert updated_agent.dirty_state?
      assert :queue.len(updated_agent.pending_instructions) == 1
    end
  end
end
