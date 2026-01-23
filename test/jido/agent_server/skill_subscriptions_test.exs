defmodule JidoTest.AgentServer.SkillSubscriptionsTest do
  use JidoTest.Case, async: false

  alias Jido.Sensor.Runtime

  @moduletag :capture_log

  # ---------------------------------------------------------------------------
  # Test Sensor Module
  # ---------------------------------------------------------------------------

  defmodule TestSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "test_sensor",
      description: "A sensor for testing skill subscriptions",
      schema:
        Zoi.object(
          %{
            emit_on_init: Zoi.boolean() |> Zoi.default(false),
            signal_type: Zoi.string() |> Zoi.default("test.sensor.event")
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      state = %{
        config: config,
        context: context,
        event_count: 0
      }

      if config.emit_on_init do
        signal =
          Jido.Signal.new!(%{
            source: "/sensor/test",
            type: config.signal_type,
            data: %{event: :initialized, context_keys: Map.keys(context)}
          })

        {:ok, state, [{:emit, signal}]}
      else
        {:ok, state}
      end
    end

    @impl Jido.Sensor
    def handle_event({:trigger, value}, state) do
      signal =
        Jido.Signal.new!(%{
          source: "/sensor/test",
          type: state.config.signal_type,
          data: %{value: value, count: state.event_count + 1}
        })

      new_state = %{state | event_count: state.event_count + 1}
      {:ok, new_state, [{:emit, signal}]}
    end

    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  defmodule SecondTestSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "second_test_sensor",
      description: "A second sensor for multi-sensor tests",
      schema:
        Zoi.object(
          %{
            sensor_id: Zoi.string() |> Zoi.default("second")
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      signal =
        Jido.Signal.new!(%{
          source: "/sensor/#{config.sensor_id}",
          type: "second.sensor.init",
          data: %{sensor_id: config.sensor_id, agent_id: context.agent_id}
        })

      {:ok, %{config: config, context: context}, [{:emit, signal}]}
    end

    @impl Jido.Sensor
    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Test Action Module
  # ---------------------------------------------------------------------------

  defmodule SimpleAction do
    @moduledoc false
    use Jido.Action,
      name: "simple_action",
      schema: []

    def run(_params, _context), do: {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Test Skill Modules
  # ---------------------------------------------------------------------------

  defmodule SkillWithSensor do
    @moduledoc false
    use Jido.Skill,
      name: "skill_with_sensor",
      state_key: :with_sensor,
      actions: [JidoTest.AgentServer.SkillSubscriptionsTest.SimpleAction]

    @impl Jido.Skill
    def subscriptions(_config, context) do
      [
        {JidoTest.AgentServer.SkillSubscriptionsTest.TestSensor,
         %{emit_on_init: true, signal_type: "skill.sensor.ready", agent_ref: context.agent_ref}}
      ]
    end
  end

  defmodule SkillWithMultipleSensors do
    @moduledoc false
    use Jido.Skill,
      name: "skill_with_multiple_sensors",
      state_key: :multi_sensors,
      actions: [JidoTest.AgentServer.SkillSubscriptionsTest.SimpleAction]

    @impl Jido.Skill
    def subscriptions(_config, context) do
      [
        {JidoTest.AgentServer.SkillSubscriptionsTest.TestSensor,
         %{emit_on_init: true, signal_type: "first.sensor.event", agent_ref: context.agent_ref}},
        {JidoTest.AgentServer.SkillSubscriptionsTest.SecondTestSensor,
         %{sensor_id: "multi-test", agent_ref: context.agent_ref}}
      ]
    end
  end

  defmodule SkillWithNoSubscriptions do
    @moduledoc false
    use Jido.Skill,
      name: "skill_with_no_subscriptions",
      state_key: :no_subs,
      actions: [JidoTest.AgentServer.SkillSubscriptionsTest.SimpleAction]

    @impl Jido.Skill
    def subscriptions(_config, _context) do
      []
    end
  end

  defmodule SkillWithoutSubscriptionsCallback do
    @moduledoc false
    use Jido.Skill,
      name: "skill_without_subscriptions_callback",
      state_key: :no_callback,
      actions: [JidoTest.AgentServer.SkillSubscriptionsTest.SimpleAction]
  end

  # ---------------------------------------------------------------------------
  # Test Agent Modules
  # ---------------------------------------------------------------------------

  defmodule AgentWithSensorSkill do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_sensor_skill",
      skills: [JidoTest.AgentServer.SkillSubscriptionsTest.SkillWithSensor]
  end

  defmodule AgentWithMultiSensorSkill do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_multi_sensor_skill",
      skills: [JidoTest.AgentServer.SkillSubscriptionsTest.SkillWithMultipleSensors]
  end

  defmodule AgentWithNoSubscriptionsSkill do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_no_subs_skill",
      skills: [JidoTest.AgentServer.SkillSubscriptionsTest.SkillWithNoSubscriptions]
  end

  defmodule AgentWithSkillWithoutCallback do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_skill_without_callback",
      skills: [JidoTest.AgentServer.SkillSubscriptionsTest.SkillWithoutSubscriptionsCallback]
  end

  defmodule AgentWithMultipleSkills do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_multiple_skills",
      skills: [
        JidoTest.AgentServer.SkillSubscriptionsTest.SkillWithSensor,
        JidoTest.AgentServer.SkillSubscriptionsTest.SkillWithMultipleSensors
      ]
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "skill subscription sensors during post_init" do
    test "starts subscription sensor during post_init", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorSkill, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} ->
          match?({:sensor, _, _}, tag)
        end)

      assert length(sensor_children) == 1

      [{tag, child_info}] = sensor_children
      assert {:sensor, SkillWithSensor, TestSensor} = tag
      assert Process.alive?(child_info.pid)

      GenServer.stop(pid)
    end

    test "sensor is monitored by AgentServer", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorSkill, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

      [{_tag, child_info}] = sensor_children
      assert child_info.ref != nil

      GenServer.stop(child_info.pid)

      eventually_state(pid, fn state ->
        sensor_count =
          state.children
          |> Enum.count(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

        sensor_count == 0
      end)

      GenServer.stop(pid)
    end
  end

  describe "sensor context" do
    test "sensor receives correct context with agent_ref, agent_id, agent_module, skill_spec", %{
      jido: jido
    } do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorSkill, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

      [{_tag, child_info}] = sensor_children

      sensor_state = :sys.get_state(child_info.pid)

      assert is_map(sensor_state.context)
      assert is_binary(sensor_state.context.agent_id)
      assert sensor_state.context.agent_module == AgentWithSensorSkill
      assert is_tuple(sensor_state.context.agent_ref)
      assert sensor_state.context.skill_spec != nil
      assert sensor_state.context.skill_spec.module == SkillWithSensor
      assert sensor_state.context.jido_instance == jido

      GenServer.stop(pid)
    end
  end

  describe "signal delivery to agent" do
    test "sensor signals are delivered to the agent", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorSkill, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

      [{_tag, child_info}] = sensor_children

      Runtime.event(child_info.pid, {:trigger, :test_value})

      Process.sleep(50)

      GenServer.stop(pid)
    end
  end

  describe "multiple sensors from same skill" do
    test "starts all sensors from skill with multiple subscriptions", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithMultiSensorSkill, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

      assert length(sensor_children) == 2

      sensor_modules =
        sensor_children
        |> Enum.map(fn {{:sensor, _skill, sensor_mod}, _} -> sensor_mod end)
        |> Enum.sort()

      assert sensor_modules == [SecondTestSensor, TestSensor]

      Enum.each(sensor_children, fn {_tag, child_info} ->
        assert Process.alive?(child_info.pid)
      end)

      GenServer.stop(pid)
    end
  end

  describe "multiple skills with sensors" do
    test "starts sensors from all skills", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithMultipleSkills, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

      assert length(sensor_children) == 3

      skill_sensor_pairs =
        sensor_children
        |> Enum.map(fn {{:sensor, skill, sensor}, _} -> {skill, sensor} end)
        |> Enum.sort()

      assert {SkillWithMultipleSensors, SecondTestSensor} in skill_sensor_pairs
      assert {SkillWithMultipleSensors, TestSensor} in skill_sensor_pairs
      assert {SkillWithSensor, TestSensor} in skill_sensor_pairs

      GenServer.stop(pid)
    end
  end

  describe "skill with empty subscriptions" do
    test "skill returning empty list works fine", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithNoSubscriptionsSkill, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

      assert sensor_children == []

      GenServer.stop(pid)
    end

    test "skill without subscriptions callback works fine", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSkillWithoutCallback, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

      assert sensor_children == []

      GenServer.stop(pid)
    end
  end

  describe "sensor child tracking" do
    test "sensors are tracked in agent's children map", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorSkill, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      tag = {:sensor, SkillWithSensor, TestSensor}
      assert Map.has_key?(state.children, tag)

      child_info = Map.get(state.children, tag)
      assert child_info.module == TestSensor
      assert child_info.meta.skill == SkillWithSensor
      assert child_info.meta.sensor == TestSensor

      GenServer.stop(pid)
    end
  end

  describe "sensor cleanup on AgentServer stop" do
    test "sensors are cleaned up when AgentServer stops", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorSkill, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      sensor_children =
        state.children
        |> Enum.filter(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

      sensor_pids = Enum.map(sensor_children, fn {_, info} -> info.pid end)

      assert Enum.all?(sensor_pids, &Process.alive?/1)

      GenServer.stop(pid)

      eventually(fn ->
        not Process.alive?(pid)
      end)
    end
  end
end
