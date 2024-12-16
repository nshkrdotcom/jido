defmodule JidoTest.AgentTest do
  use ExUnit.Case, async: true
  alias Jido.Actions.Basic.Log
  alias Jido.Actions.Basic.Sleep
  alias JidoTest.SimpleAgent

  describe "SimpleAgent.new/1" do
    test "creates an agent with default values" do
      agent = SimpleAgent.new()
      assert agent.id != nil
      assert agent.location == :home
      assert agent.battery_level == 100
    end

    test "creates an agent with custom id" do
      custom_id = "custom_id"
      agent = SimpleAgent.new(custom_id)
      assert agent.id == custom_id
    end

    test "generates unique ids for multiple agents" do
      agent1 = SimpleAgent.new()
      agent2 = SimpleAgent.new()
      assert agent1.id != agent2.id
    end
  end

  describe "SimpleAgent metadata" do
    test "to_json/0 returns agent metadata" do
      json = SimpleAgent.to_json()
      assert json.name == "SimpleBot"
      assert is_list(json.schema)
    end

    test "__agent_metadata__/0 returns agent metadata" do
      metadata = SimpleAgent.__agent_metadata__()
      assert metadata.name == "SimpleBot"
      assert is_list(metadata.schema)
    end

    test "name/0 returns the agent name" do
      assert SimpleAgent.name() == "SimpleBot"
    end

    test "description/0 returns the agent description" do
      assert SimpleAgent.description() == nil
    end

    test "category/0 returns the agent category" do
      assert SimpleAgent.category() == nil
    end

    test "tags/0 returns the agent tags" do
      assert SimpleAgent.tags() == []
    end

    test "vsn/0 returns the agent version" do
      assert SimpleAgent.vsn() == nil
    end

    test "schema/0 returns the agent schema" do
      schema = SimpleAgent.schema()
      assert Keyword.has_key?(schema, :location)
      assert Keyword.has_key?(schema, :battery_level)
    end
  end

  describe "SimpleAgent.set/2" do
    setup do
      {:ok, agent: SimpleAgent.new()}
    end

    test "updates agent attributes", %{agent: agent} do
      {:ok, updated_agent} = SimpleAgent.set(agent, %{location: :office, battery_level: 80})
      assert updated_agent.location == :office
      assert updated_agent.battery_level == 80
    end

    test "returns error for invalid attributes", %{agent: agent} do
      {:error, error_message} =
        SimpleAgent.set(agent, %{location: "invalid", battery_level: "full"})

      assert error_message =~ "Invalid parameters for Agent"
    end

    test "handles partial updates", %{agent: agent} do
      {:ok, updated_agent} = SimpleAgent.set(agent, %{location: :park})
      assert updated_agent.location == :park
      assert updated_agent.battery_level == 100
    end

    test "handles empty update", %{agent: agent} do
      {:ok, updated_agent} = SimpleAgent.set(agent, %{})
      assert updated_agent == agent
    end
  end

  describe "SimpleAgent.validate/1" do
    test "returns :ok for valid agent state" do
      agent = SimpleAgent.new()
      assert {:ok, ^agent} = SimpleAgent.validate(agent)
    end

    test "returns error for invalid agent state" do
      agent = SimpleAgent.new()
      invalid_agent = %{agent | battery_level: "not a number"}
      assert {:error, error_message} = SimpleAgent.validate(invalid_agent)
      assert error_message =~ "Invalid parameters for Agent"
    end

    test "validates custom attributes" do
      agent = SimpleAgent.new()
      invalid_agent = Map.put(agent, :custom_field, "invalid")
      assert {:error, error_message} = SimpleAgent.validate(invalid_agent)
      assert error_message =~ "Invalid parameters for Agent"
    end
  end

  describe "SimpleAgent.plan/1" do
    test "returns an ActionSet with a plan" do
      agent = SimpleAgent.new()
      assert {:ok, action_set} = SimpleAgent.plan(agent)
      assert %Jido.ActionSet{} = action_set
      assert action_set.agent == agent
      assert is_list(action_set.plan)
    end

    test "plan includes expected actions" do
      agent = SimpleAgent.new()
      {:ok, action_set} = SimpleAgent.plan(agent)
      [action1, action2, action3] = action_set.plan
      assert action1 == {Log, message: "Hello, world!"}
      assert action2 == {Sleep, duration: 50}
      assert action3 == {Log, message: "Goodbye, world!"}
    end
  end

  describe "SimpleAgent.run/1" do
    setup do
      agent = SimpleAgent.new()
      {:ok, action_set} = SimpleAgent.plan(agent)
      {:ok, agent: agent, action_set: action_set}
    end

    test "executes a plan and returns updated agent state", %{action_set: action_set} do
      assert {:ok, updated_agent} = SimpleAgent.run(action_set)
      assert %SimpleAgent{} = updated_agent
      assert updated_agent != action_set.agent
    end

    test "returns error when plan execution fails", %{agent: agent} do
      invalid_action_set = %Jido.ActionSet{agent: agent, plan: [{:invalid_action, []}]}
      assert {:error, %Jido.Error{type: :invalid_action}} = SimpleAgent.run(invalid_action_set)
    end

    test "handles empty plan", %{agent: agent} do
      empty_action_set = %Jido.ActionSet{agent: agent, plan: []}
      assert {:ok, ^agent} = SimpleAgent.run(empty_action_set)
    end
  end

  describe "SimpleAgent.act/2" do
    setup do
      {:ok, agent: SimpleAgent.new()}
    end

    test "updates state, plans, and executes actions", %{agent: agent} do
      new_attrs = %{location: :office}
      assert {:ok, updated_agent} = SimpleAgent.act(agent, new_attrs)
      assert updated_agent.location == :office
      assert updated_agent != agent
    end

    test "returns error when update fails", %{agent: agent} do
      invalid_attrs = %{battery_level: "not a number"}
      assert {:error, reason} = SimpleAgent.act(agent, invalid_attrs)
      assert is_binary(reason)
    end

    test "handles empty update", %{agent: agent} do
      assert {:ok, updated_agent} = SimpleAgent.act(agent, %{})
      # Because the plan was still executed
      assert updated_agent != agent
    end

    test "updates multiple attributes", %{agent: agent} do
      new_attrs = %{location: :park, battery_level: 75}
      assert {:ok, updated_agent} = SimpleAgent.act(agent, new_attrs)
      assert updated_agent.location == :park
      assert updated_agent.battery_level == 75
    end
  end
end
