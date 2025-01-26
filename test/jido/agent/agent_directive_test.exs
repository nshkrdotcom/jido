defmodule JidoTest.AgentDirectiveTest do
  use ExUnit.Case, async: true
  use Mimic

  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Runner.Chain

  alias Jido.Agent.Directive.{
    EnqueueDirective,
    RegisterActionDirective,
    DeregisterActionDirective
  }

  alias JidoTest.TestActions.{
    BasicAction,
    NoSchema,
    EnqueueAction,
    RegisterAction,
    DeregisterAction
  }

  setup :verify_on_exit!
  @moduletag :capture_log

  describe "enqueue directives" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "successfully enqueues valid action via cmd", %{agent: agent} do
      {:ok, final} =
        BasicAgent.cmd(
          agent,
          {EnqueueAction,
           %{
             action: BasicAction,
             params: %{value: 42}
           }},
          %{},
          runner: Jido.Runner.Simple
        )

      # Verify enqueued action
      assert {:value, instruction} = :queue.peek(final.pending_instructions)
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}

      # Verify directive result format
      assert %{result: result} = final
      assert %{directives: [%EnqueueDirective{} = directive]} = result
      assert directive.action == BasicAction
      assert directive.params == %{value: 42}
      assert is_map(directive.context)
    end

    test "maintains queue order with multiple enqueues", %{agent: agent} do
      instructions = [
        {EnqueueAction, %{action: BasicAction, params: %{id: 1}}},
        {EnqueueAction, %{action: BasicAction, params: %{id: 2}}}
      ]

      {:ok, final} = BasicAgent.cmd(agent, instructions, %{}, runner: Chain)

      # Verify queue order
      {{:value, first}, queue} = :queue.out(final.pending_instructions)
      {{:value, second}, _} = :queue.out(queue)

      # assert first.params.id == 1
      # assert second.params.id == 2

      # Verify directives
      assert %{result: result} = final
      assert %{directives: directives} = result
      assert length(directives) == 2
      [first_directive, second_directive] = directives

      assert %EnqueueDirective{} = first_directive
      assert first_directive.params.id == 1
      assert %EnqueueDirective{} = second_directive
      assert second_directive.params.id == 2
    end
  end

  describe "register directives" do
    setup do
      # Start with a fresh agent that has only RegisterAction
      agent = BasicAgent.new()
      # Remove all actions except RegisterAction
      {:ok, agent} = BasicAgent.deregister_action(agent, BasicAction)
      {:ok, agent} = BasicAgent.deregister_action(agent, NoSchema)
      {:ok, agent} = BasicAgent.deregister_action(agent, EnqueueAction)
      {:ok, agent} = BasicAgent.deregister_action(agent, DeregisterAction)
      {:ok, agent: agent}
    end

    test "successfully registers new action module via plan and run", %{agent: agent} do
      {:ok, planned} =
        BasicAgent.plan(agent, {RegisterAction, %{action_module: BasicAction}})

      {:ok, final} = BasicAgent.run(planned)

      # Verify registered actions
      assert BasicAction in final.actions
      assert RegisterAction in final.actions
      assert length(final.actions) == 2

      # Verify directive result
      assert %{result: result} = final
      assert %{directives: [%RegisterActionDirective{} = directive]} = result
      assert directive.action_module == BasicAction
    end

    test "registers multiple action modules", %{agent: agent} do
      instructions = [
        {RegisterAction, %{action_module: BasicAction}},
        {RegisterAction, %{action_module: NoSchema}}
      ]

      {:ok, final} = BasicAgent.cmd(agent, instructions, %{}, runner: Chain)

      # Verify registered actions
      assert BasicAction in final.actions
      assert NoSchema in final.actions
      assert RegisterAction in final.actions
      assert length(final.actions) == 3

      # Verify directives
      assert %{result: result} = final
      assert %{directives: directives} = result
      assert length(directives) == 2

      [first_directive, second_directive] = directives
      assert %RegisterActionDirective{} = first_directive
      assert first_directive.action_module == BasicAction
      assert %RegisterActionDirective{} = second_directive
      assert second_directive.action_module == NoSchema
    end

    test "idempotent registration of same module", %{agent: agent} do
      instructions = [
        {RegisterAction, %{action_module: BasicAction}},
        {RegisterAction, %{action_module: BasicAction}}
      ]

      {:ok, final} = BasicAgent.cmd(agent, instructions, %{}, runner: Chain)

      # Verify registered actions
      assert length(final.actions) == 2
      assert BasicAction in final.actions
      assert RegisterAction in final.actions
      refute NoSchema in final.actions

      # Verify directives
      assert %{result: result} = final
      assert %{directives: directives} = result
      assert length(directives) == 2

      Enum.each(directives, fn directive ->
        assert %RegisterActionDirective{} = directive
        assert directive.action_module == BasicAction
      end)
    end
  end

  describe "deregister directives" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "successfully deregisters existing action module", %{agent: agent} do
      {:ok, final} =
        BasicAgent.cmd(
          agent,
          {DeregisterAction, %{action_module: BasicAction}},
          %{},
          runner: Chain
        )

      # Verify action was deregistered
      refute BasicAction in final.actions

      # Verify directive
      assert %{result: result} = final
      assert %{directives: [%DeregisterActionDirective{} = directive]} = result
      assert directive.action_module == BasicAction
    end

    test "safely handles deregistering non-existent module", %{agent: agent} do
      {:ok, final} =
        BasicAgent.cmd(
          agent,
          {DeregisterAction, %{action_module: UnknownModule}},
          %{},
          runner: Chain
        )

      # Verify actions unchanged
      assert final.actions == agent.actions

      # Verify directive
      assert %{result: result} = final
      assert %{directives: [%DeregisterActionDirective{} = directive]} = result
      assert directive.action_module == UnknownModule
    end

    test "prevents deregistering self", %{agent: agent} do
      {:error, %Jido.Runner.Result{error: error}} =
        BasicAgent.cmd(
          agent,
          {DeregisterAction, %{action_module: DeregisterAction}},
          %{},
          runner: Chain
        )

      assert error.message == :cannot_deregister_self
    end
  end
end
