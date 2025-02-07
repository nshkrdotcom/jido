defmodule JidoTest.DirectiveTest do
  use ExUnit.Case, async: true
  use Mimic

  @moduletag :capture_log

  alias Jido.Agent.Directive

  alias Jido.Agent.Directive.{
    Enqueue,
    RegisterAction,
    DeregisterAction,
    Spawn,
    Kill
  }

  alias Jido.Agent.Server.State, as: ServerState
  alias JidoTest.TestAgents.FullFeaturedAgent
  alias JidoTest.TestActions.Add

  setup :verify_on_exit!

  describe "directive filtering" do
    test "agent_directive? correctly identifies directives" do
      # Agent directives
      assert Directive.agent_directive?(%Enqueue{action: :test})
      assert Directive.agent_directive?(%RegisterAction{action_module: Add})
      assert Directive.agent_directive?(%DeregisterAction{action_module: Add})

      # Server directives
      refute Directive.agent_directive?(%Spawn{module: Add, args: []})
      refute Directive.agent_directive?(%Kill{pid: self()})
      refute Directive.agent_directive?(:not_a_directive)
    end

    test "split_directives separates agent and server directives" do
      directives = [
        %Enqueue{action: :test},
        %Spawn{module: Add, args: []},
        %RegisterAction{action_module: Add},
        %Kill{pid: self()},
        %DeregisterAction{action_module: Add}
      ]

      {agent_directives, server_directives} = Directive.split_directives(directives)

      assert length(agent_directives) == 3
      assert length(server_directives) == 2

      assert Enum.all?(agent_directives, &Directive.agent_directive?/1)
      refute Enum.any?(server_directives, &Directive.agent_directive?/1)
    end
  end

  describe "directive application to Agent" do
    setup do
      agent = FullFeaturedAgent.new("test-agent")
      # Start with a clean agent (no actions)
      agent = %{agent | actions: []}
      {:ok, agent: agent}
    end

    test "handles single directive", %{agent: agent} do
      directive = %Enqueue{action: Add, params: %{value: 1}}
      {:ok, updated_agent, unapplied} = Directive.apply_agent_directive(agent, [directive])

      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == Add
      assert instruction.params == %{value: 1}
      assert unapplied == []
    end

    test "handles multiple directives in order", %{agent: agent} do
      directives = [
        %RegisterAction{action_module: Add},
        %Enqueue{action: Add, params: %{value: 1}},
        %Enqueue{action: Add, params: %{value: 2}}
      ]

      {:ok, updated_agent, unapplied} = Directive.apply_agent_directive(agent, directives)

      assert Add in updated_agent.actions
      assert :queue.len(updated_agent.pending_instructions) == 2
      assert unapplied == []

      {{:value, first}, q1} = :queue.out(updated_agent.pending_instructions)
      {{:value, second}, _} = :queue.out(q1)

      assert first.params.value == 1
      assert second.params.value == 2
    end

    test "stops on first error", %{agent: agent} do
      directives = [
        %Enqueue{action: Add, params: %{value: 1}},
        # Invalid
        %Enqueue{action: nil},
        %Enqueue{action: Add, params: %{value: 2}}
      ]

      assert {:error, :invalid_action} = Directive.apply_agent_directive(agent, directives)
      assert :queue.is_empty(agent.pending_instructions)
    end

    test "returns server directives as unapplied", %{agent: agent} do
      directives = [
        %Enqueue{action: Add, params: %{value: 1}},
        %Spawn{module: Add, args: []},
        %RegisterAction{action_module: Add},
        %Kill{pid: self()}
      ]

      {:ok, updated_agent, unapplied} = Directive.apply_agent_directive(agent, directives)

      # Verify agent directives were applied
      assert :queue.len(updated_agent.pending_instructions) == 1
      assert Add in updated_agent.actions

      # Verify server directives were returned as unapplied
      assert length(unapplied) == 2
      assert Enum.any?(unapplied, fn d -> match?(%Spawn{}, d) end)
      assert Enum.any?(unapplied, fn d -> match?(%Kill{}, d) end)
    end

    test "validation of directives", %{agent: agent} do
      # Invalid agent directive
      assert {:error, :invalid_action} =
               Directive.apply_agent_directive(agent, [%Enqueue{action: nil}])

      # Invalid server directive
      assert {:error, :invalid_module} =
               Directive.apply_agent_directive(agent, [%Spawn{module: nil, args: []}])

      # Invalid directive type
      assert {:error, :invalid_directive} =
               Directive.apply_agent_directive(agent, [:not_a_directive])
    end
  end

  describe "directive application to ServerState" do
    setup do
      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | actions: []}
      state = %ServerState{agent: agent}
      {:ok, state: state}
    end

    test "handles server directives", %{state: state} do
      directives = [
        %Spawn{module: Add, args: []},
        %Kill{pid: self()}
      ]

      {:ok, updated_state, unapplied} = Directive.apply_server_directive(state, directives)

      # For now, server state should be unchanged
      assert updated_state == state
      # Server directives should be returned as unapplied
      assert unapplied == directives
    end

    test "handles mixed directives", %{state: state} do
      server_directives = [
        %Spawn{module: Add, args: []},
        %Kill{pid: self()}
      ]

      agent_directives = [
        %Enqueue{action: Add, params: %{value: 1}},
        %RegisterAction{action_module: Add}
      ]

      directives = agent_directives ++ server_directives

      {:ok, updated_state, unapplied} = Directive.apply_server_directive(state, directives)

      # Server state should be unchanged
      assert updated_state == state
      # All directives should be returned as unapplied in their original order
      assert unapplied == server_directives
    end

    test "propagates agent directive errors", %{state: state} do
      directives = [
        # Invalid
        %Enqueue{action: nil},
        %Spawn{module: Add, args: []}
      ]

      assert {:error, :invalid_action} = Directive.apply_server_directive(state, directives)
    end
  end
end
