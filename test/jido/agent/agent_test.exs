defmodule JidoTest.AgentTest do
  use ExUnit.Case, async: true

  alias JidoTest.TestAgents.{BasicAgent, AdvancedAgent, NoSchemaAgent}

  @moduletag :capture_log

  describe "agent creation" do
    test "creates basic agent with defaults" do
      agent = BasicAgent.new()

      assert agent.id != nil
      assert agent.state.location == :home
      assert agent.state.battery_level == 100
      assert agent.dirty_state? == false
      assert agent.pending == :queue.new()
    end

    test "creates agent with custom id" do
      custom_id = "test_id"
      agent = BasicAgent.new(custom_id)
      assert agent.id == custom_id
    end

    test "creates agent without schema" do
      agent = NoSchemaAgent.new()

      assert agent.id != nil
      assert agent.dirty_state? == false
      assert agent.pending == :queue.new()

      # Should not have schema-defined fields
      refute Map.has_key?(agent, :location)
      refute Map.has_key?(agent, :battery_level)
    end

    test "generates unique ids for multiple agents" do
      agent1 = BasicAgent.new()
      agent2 = BasicAgent.new()
      refute agent1.id == agent2.id
    end
  end

  describe "agent metadata" do
    test "provides correct metadata for basic agent" do
      assert BasicAgent.name() == "BasicAgent"
      assert BasicAgent.description() == nil
      assert BasicAgent.category() == nil
      assert BasicAgent.tags() == []
      assert BasicAgent.vsn() == nil

      json = BasicAgent.to_json()
      assert json.name == "BasicAgent"
      assert is_list(json.schema)
    end

    test "provides correct metadata for advanced agent" do
      assert AdvancedAgent.name() == "AdvancedAgent"
      assert AdvancedAgent.description() == "Test agent with hooks"
      assert AdvancedAgent.category() == "test"
      assert AdvancedAgent.tags() == ["test", "hooks"]
      assert AdvancedAgent.vsn() == "1.0.0"

      json = AdvancedAgent.to_json()
      assert json.name == "AdvancedAgent"
      assert json.description == "Test agent with hooks"
    end

    test "provides correct metadata for schema-less agent" do
      assert NoSchemaAgent.name() == "NoSchemaAgent"
      assert NoSchemaAgent.description() == nil
      assert NoSchemaAgent.category() == nil
      assert NoSchemaAgent.tags() == []
      assert NoSchemaAgent.vsn() == nil

      json = NoSchemaAgent.to_json()
      assert json.name == "NoSchemaAgent"
      assert json.schema == []
    end
  end

  describe "state management" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "updates agent state", %{agent: agent} do
      {:ok, updated} =
        BasicAgent.set(agent, %{
          location: :office,
          battery_level: 80
        })

      assert updated.state.location == :office
      assert updated.state.battery_level == 80
      assert updated.dirty_state? == true
    end

    test "validates state updates", %{agent: agent} do
      assert {:error, error} =
               BasicAgent.set(agent, %{
                 # Invalid type
                 location: 123,
                 # Invalid type
                 battery_level: "full"
               })

      assert error =~ "Invalid parameters for Agent"
    end

    test "handles empty updates", %{agent: agent} do
      {:ok, updated} = BasicAgent.set(agent, %{})
      assert updated == agent
      assert updated.dirty_state? == false
    end

    test "allows unknown fields in state", %{agent: agent} do
      # Set boolean
      {:ok, updated} = BasicAgent.set(agent, %{unknown_field: true})
      assert updated.state.unknown_field == true
      assert updated.dirty_state? == true

      # Set integer
      {:ok, updated} = BasicAgent.set(updated, %{unknown_field: 42})
      assert updated.state.unknown_field == 42
      assert updated.dirty_state? == true

      # Set string
      {:ok, updated} = BasicAgent.set(updated, %{unknown_field: "hello"})
      assert updated.state.unknown_field == "hello"
      assert updated.dirty_state? == true
    end

    test "validates against schema", %{agent: agent} do
      invalid_agent = %{agent | state: Map.put(agent.state, :battery_level, "invalid")}
      assert {:error, error} = BasicAgent.validate(invalid_agent)
      assert error =~ "Invalid parameters for Agent"
    end

    test "allows any state updates for schema-less agent" do
      agent = NoSchemaAgent.new()

      {:ok, updated} =
        NoSchemaAgent.set(agent, %{
          custom_field: "value",
          another_field: 123
        })

      assert updated.state.custom_field == "value"
      assert updated.state.another_field == 123
      assert updated.dirty_state? == true

      # Should always validate since there's no schema
      assert {:ok, _} = NoSchemaAgent.validate(updated)
    end
  end

  describe "action management" do
    setup do
      agent = AdvancedAgent.new()
      {:ok, agent: agent}
    end

    test "registers actions on creation", %{agent: agent} do
      actions = AdvancedAgent.registered_actions(agent)
      assert JidoTest.TestActions.Add in actions
      assert JidoTest.TestActions.Multiply in actions
      assert JidoTest.TestActions.DelayAction in actions
      assert JidoTest.TestActions.ContextAction in actions
    end

    test "validates registered actions", %{agent: agent} do
      assert length(AdvancedAgent.registered_actions(agent)) == 4
      assert Enum.all?(AdvancedAgent.registered_actions(agent), &is_atom/1)
    end
  end

  describe "plan/3" do
    setup do
      agent = AdvancedAgent.new()
      {:ok, agent: agent}
    end

    test "plans basic action", %{agent: agent} do
      {:ok, planned} = AdvancedAgent.plan(agent, JidoTest.TestActions.Add, %{value: 42})
      assert :queue.len(planned.pending) == 1

      actions = :queue.to_list(planned.pending)
      assert [{JidoTest.TestActions.Add, %{value: 42}}] = actions
    end

    test "plans multiple actions", %{agent: agent} do
      {:ok, planned} =
        AdvancedAgent.plan(
          agent,
          [
            {JidoTest.TestActions.Add, %{value: 10}},
            {JidoTest.TestActions.Multiply, %{value: 2}},
            {JidoTest.TestActions.DelayAction, %{delay: 100}}
          ],
          %{}
        )

      assert :queue.len(planned.pending) == 3

      actions = :queue.to_list(planned.pending)

      assert [
               {JidoTest.TestActions.Add, %{value: 10}},
               {JidoTest.TestActions.Multiply, %{value: 2}},
               {JidoTest.TestActions.DelayAction, %{delay: 100}}
             ] = actions
    end

    test "handles unregistered actions", %{agent: agent} do
      assert {:error, error} = AdvancedAgent.plan(agent, UnknownAction, %{})
      assert error.message =~ "Action not registered"
    end
  end

  describe "run/2" do
    setup do
      agent = AdvancedAgent.new()
      {:ok, agent: agent}
    end

    test "executes add action", %{agent: agent} do
      {:ok, planned} = AdvancedAgent.plan(agent, JidoTest.TestActions.Add, %{value: 10})
      {:ok, final} = AdvancedAgent.run(planned)
      assert final.pending == :queue.new()
      assert final.dirty_state? == false
    end

    test "run with apply_state: true updates agent state", %{agent: agent} do
      {:ok, planned} =
        AdvancedAgent.plan(agent, JidoTest.TestActions.ContextAction, %{
          input: "test",
          location: :work_area
        })

      {:ok, final} = AdvancedAgent.run(planned, apply_state: true)

      assert final.state.location == :work_area
      assert final.pending == :queue.new()
      assert final.dirty_state? == false
    end

    test "run with apply_state: false preserves original state", %{agent: agent} do
      {:ok, planned} =
        AdvancedAgent.plan(agent, JidoTest.TestActions.ContextAction, %{
          input: "test",
          location: :work_area
        })

      {:ok, final} = AdvancedAgent.run(planned, apply_state: false)

      # Original location preserved
      assert final.state.location == :home
      # Result contains new state
      assert Map.get(final.result, :location) == :work_area
      assert final.pending == :queue.new()
      assert final.dirty_state? == false
    end

    test "runs multiple actions in sequence", %{agent: agent} do
      {:ok, planned} =
        AdvancedAgent.plan(
          agent,
          [
            {JidoTest.TestActions.Add, %{value: 10}},
            {JidoTest.TestActions.Multiply, %{value: 2}},
            {JidoTest.TestActions.DelayAction, %{delay: 100}}
          ],
          %{}
        )

      {:ok, final} = AdvancedAgent.run(planned)

      assert final.pending == :queue.new()
      assert final.dirty_state? == false
    end
  end

  describe "combined operations with plan/3" do
    setup do
      agent = AdvancedAgent.new()
      {:ok, agent: agent}
    end

    test "validates, plans and executes", %{agent: agent} do
      {:ok, planned} =
        AdvancedAgent.plan(agent, JidoTest.TestActions.ContextAction, %{
          input: "test",
          location: :work_area
        })

      {:ok, final} = AdvancedAgent.run(planned)

      assert final.state.location == :work_area
      assert final.pending == :queue.new()
      assert final.dirty_state? == false
    end

    test "preserves state with apply_state: false", %{agent: agent} do
      {:ok, planned} =
        AdvancedAgent.plan(agent, JidoTest.TestActions.ContextAction, %{
          input: "test",
          location: :work_area
        })

      {:ok, final_agent} = AdvancedAgent.run(planned, apply_state: false)

      # Original location
      assert final_agent.state.location == :home
      assert final_agent.pending == :queue.new()
      assert final_agent.dirty_state? == false
      # Result should have the new location
      assert final_agent.result.location == :work_area
    end
  end

  describe "queue management" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "resets pending queue", %{agent: agent} do
      {:ok, planned} = BasicAgent.plan(agent, JidoTest.TestActions.BasicAction, %{value: 1})
      assert BasicAgent.pending?(planned) > 0

      {:ok, reset} = BasicAgent.reset(planned)
      assert BasicAgent.pending?(reset) == 0
    end

    test "reports pending count", %{agent: agent} do
      assert BasicAgent.pending?(agent) == 0

      {:ok, planned} = BasicAgent.plan(agent, JidoTest.TestActions.BasicAction, %{value: 1})
      assert BasicAgent.pending?(planned) > 0
    end
  end

  describe "cmd/4" do
    setup do
      agent = AdvancedAgent.new()
      {:ok, agent: agent}
    end

    test "executes single action with params", %{agent: agent} do
      {:ok, final} =
        AdvancedAgent.cmd(agent, JidoTest.TestActions.ContextAction, %{
          input: "test",
          location: :work_area
        })

      assert final.state.location == :work_area
      assert final.pending == :queue.new()
      assert final.dirty_state? == false
    end

    test "executes list of action tuples", %{agent: agent} do
      actions = [
        {JidoTest.TestActions.Add, %{value: 10}},
        {JidoTest.TestActions.Multiply, %{value: 2}},
        {JidoTest.TestActions.ContextAction, %{input: "test", location: :work_area}}
      ]

      {:ok, final} = AdvancedAgent.cmd(agent, actions, %{})

      assert final.state.location == :work_area
      assert final.pending == :queue.new()
      assert final.dirty_state? == false
    end

    test "preserves state with apply_state: false", %{agent: agent} do
      # Ensure agent is in home
      assert agent.state.location == :home

      {:ok, final} =
        AdvancedAgent.cmd(
          agent,
          JidoTest.TestActions.ContextAction,
          %{
            input: "test",
            location: :work_area
          },
          apply_state: false
        )

      # Agent state is unchanged
      assert final.state.location == :home
      assert final.pending == :queue.new()
      assert final.dirty_state? == false
      # Result contains new state
      assert final.result.location == :work_area
    end

    test "handles invalid actions", %{agent: agent} do
      assert {:error, error} = AdvancedAgent.cmd(agent, UnknownAction, %{})
      assert error.message =~ "Action not registered"
    end

    test "validates params before execution", %{agent: agent} do
      assert {:error, %Jido.Error{} = error} =
               AdvancedAgent.cmd(agent, JidoTest.TestActions.ContextAction, %{
                 # Invalid type
                 input: 123,
                 # Invalid type
                 location: :invalid
               })

      assert error.message =~ "Invalid agent state or parameters"
    end
  end
end
