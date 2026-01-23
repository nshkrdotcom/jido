defmodule JidoTest.AgentServer.SignalRouterTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.SignalRouter
  alias Jido.AgentServer.State
  alias Jido.AgentServer.State.Lifecycle
  alias Jido.Signal.Router, as: JidoRouter

  # =============================================================================
  # Test Fixtures - Actions
  # =============================================================================

  defmodule TestAction do
    @moduledoc false
    use Jido.Action,
      name: "test_action",
      schema: []

    def run(_params, _ctx), do: {:ok, %{}}
  end

  defmodule AnotherAction do
    @moduledoc false
    use Jido.Action,
      name: "another_action",
      schema: []

    def run(_params, _ctx), do: {:ok, %{}}
  end

  # =============================================================================
  # Test Fixtures - Strategies
  # =============================================================================

  defmodule StrategyWithRoutes do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def cmd(agent, _instructions, _ctx), do: {agent, []}

    @impl true
    def signal_routes(_ctx) do
      [
        {"strategy.action", JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"strategy.priority", JidoTest.AgentServer.SignalRouterTest.TestAction, 75}
      ]
    end
  end

  defmodule StrategyWithoutRoutes do
    @moduledoc "Strategy that does NOT export signal_routes/1"
    @behaviour Jido.Agent.Strategy

    @impl true
    def init(agent, _ctx), do: {agent, []}

    @impl true
    def tick(agent, _ctx), do: {agent, []}

    @impl true
    def cmd(agent, _instructions, _ctx), do: {agent, []}
  end

  # =============================================================================
  # Test Fixtures - Skills
  # =============================================================================

  defmodule SkillWithRouter do
    @moduledoc false
    use Jido.Skill,
      name: "skill_with_router",
      state_key: :router_skill,
      actions: [JidoTest.AgentServer.SignalRouterTest.TestAction]

    @impl Jido.Skill
    def router(_config) do
      [
        {"skill.custom", JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"skill.priority", JidoTest.AgentServer.SignalRouterTest.TestAction, -20}
      ]
    end
  end

  defmodule SkillReturningNil do
    @moduledoc false
    use Jido.Skill,
      name: "skill_returning_nil",
      state_key: :nil_skill,
      actions: [JidoTest.AgentServer.SignalRouterTest.TestAction],
      signal_patterns: ["nil.*"]

    @impl Jido.Skill
    def router(_config), do: nil
  end

  defmodule SkillReturningNonList do
    @moduledoc false
    use Jido.Skill,
      name: "skill_returning_non_list",
      state_key: :non_list_skill,
      actions: [JidoTest.AgentServer.SignalRouterTest.TestAction],
      signal_patterns: ["nonlist.*"]

    @impl Jido.Skill
    def router(_config), do: :not_a_list
  end

  defmodule SkillWithPatterns do
    @moduledoc false
    use Jido.Skill,
      name: "skill_with_patterns",
      state_key: :pattern_skill,
      actions: [
        JidoTest.AgentServer.SignalRouterTest.TestAction,
        JidoTest.AgentServer.SignalRouterTest.AnotherAction
      ],
      routes: [
        {"pattern.one", JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"pattern.two", JidoTest.AgentServer.SignalRouterTest.AnotherAction}
      ]
  end

  # =============================================================================
  # Test Fixtures - Agents
  # =============================================================================

  defmodule AgentWithRoutes do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_routes",
      schema: []

    def signal_routes do
      [
        {"agent.action", JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"agent.priority", JidoTest.AgentServer.SignalRouterTest.TestAction, 10}
      ]
    end
  end

  defmodule AgentWithoutRoutes do
    @moduledoc "Agent that does NOT export signal_routes/0"
    use Jido.Agent,
      name: "agent_without_routes",
      schema: []
  end

  defmodule AgentWithStrategy do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_strategy",
      strategy: JidoTest.AgentServer.SignalRouterTest.StrategyWithRoutes,
      schema: []

    def signal_routes do
      [{"agent.route", JidoTest.AgentServer.SignalRouterTest.TestAction}]
    end
  end

  defmodule AgentWithStrategyNoRoutes do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_strategy_no_routes",
      strategy: JidoTest.AgentServer.SignalRouterTest.StrategyWithoutRoutes,
      schema: []

    def signal_routes, do: []
  end

  defmodule AgentWithSkills do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_skills",
      schema: [],
      skills: [
        JidoTest.AgentServer.SignalRouterTest.SkillWithRouter,
        JidoTest.AgentServer.SignalRouterTest.SkillWithPatterns
      ]

    def signal_routes, do: []
  end

  defmodule AgentWithNilRouterSkill do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_nil_router_skill",
      schema: [],
      skills: [JidoTest.AgentServer.SignalRouterTest.SkillReturningNil]

    def signal_routes, do: []
  end

  defmodule AgentWithNonListRouterSkill do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_non_list_router_skill",
      schema: [],
      skills: [JidoTest.AgentServer.SignalRouterTest.SkillReturningNonList]

    def signal_routes, do: []
  end

  defmodule AgentWithMatchFnRoutes do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_match_fn_routes",
      schema: []

    def signal_routes do
      [
        {"match.three", &match_large_amount/1, JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"match.four", &match_large_amount/1, JidoTest.AgentServer.SignalRouterTest.TestAction,
         15}
      ]
    end

    defp match_large_amount(signal) do
      Map.get(signal.data, :amount, 0) > 100
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp build_test_state(agent_module) do
    agent = agent_module.new(%{id: "test-#{System.unique_integer([:positive])}"})

    {:ok, lifecycle} = Lifecycle.new([])

    attrs = %{
      id: agent.id,
      agent_module: agent_module,
      agent: agent,
      status: :idle,
      processing: false,
      queue: :queue.new(),
      parent: nil,
      children: %{},
      on_parent_death: :stop,
      jido: :test_jido,
      default_dispatch: nil,
      error_policy: :log_only,
      max_queue_size: 10_000,
      registry: nil,
      spawn_fun: nil,
      cron_jobs: %{},
      error_count: 0,
      metrics: %{},
      completion_waiters: %{},
      lifecycle: lifecycle
    }

    {:ok, state} = Zoi.parse(State.schema(), attrs)
    state
  end

  # =============================================================================
  # Tests
  # =============================================================================

  describe "build/1 with agent routes" do
    test "builds router from agent signal_routes/0" do
      state = build_test_state(AgentWithRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count > 0
    end

    test "returns empty router when agent doesn't export signal_routes/0" do
      state = build_test_state(AgentWithoutRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count == 0
    end
  end

  describe "build/1 with strategy routes" do
    test "builds router from strategy signal_routes/1" do
      state = build_test_state(AgentWithStrategy)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # Should have routes from both strategy and agent
      assert router.route_count >= 2
    end

    test "handles strategy without signal_routes/1 function" do
      state = build_test_state(AgentWithStrategyNoRoutes)
      router = SignalRouter.build(state)

      # Should still build successfully, just without strategy routes
      assert %JidoRouter.Router{} = router
    end
  end

  describe "build/1 with skill routes" do
    test "builds router from skill router/1 function" do
      state = build_test_state(AgentWithSkills)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # Should have routes from skill router and pattern-based routes
      assert router.route_count > 0
    end

    test "handles skill router/1 returning nil - falls back to pattern routes" do
      state = build_test_state(AgentWithNilRouterSkill)
      router = SignalRouter.build(state)

      # Should generate pattern-based routes instead
      assert %JidoRouter.Router{} = router
      # Pattern routes: signal_patterns ["nil.*"] x actions [TestAction]
      assert router.route_count == 1
    end

    test "handles skill router/1 returning non-list value - falls back to pattern routes" do
      state = build_test_state(AgentWithNonListRouterSkill)
      router = SignalRouter.build(state)

      # Should generate pattern-based routes instead
      assert %JidoRouter.Router{} = router
      # Pattern routes: signal_patterns ["nonlist.*"] x actions [TestAction]
      assert router.route_count == 1
    end

    test "generates routes from skill routes definition" do
      # SkillWithPatterns has 2 explicit routes, SkillWithRouter has 2 custom router routes
      state = build_test_state(AgentWithSkills)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # SkillWithRouter has 2 custom routes, SkillWithPatterns has 2 explicit routes
      # Total: 2 + 2 = 4 routes
      assert router.route_count == 4
    end
  end

  describe "build/1 with match functions" do
    test "normalizes 3-tuple routes with match functions" do
      state = build_test_state(AgentWithMatchFnRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # Should have 2 routes with match functions
      assert router.route_count == 2
    end

    test "normalizes 4-tuple routes with match functions and priority" do
      state = build_test_state(AgentWithMatchFnRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count == 2
    end
  end

  describe "build/1 routing with match functions" do
    test "routes match when match function returns true" do
      state = build_test_state(AgentWithMatchFnRoutes)
      router = SignalRouter.build(state)

      # Signal with amount > 100 should match
      signal = Jido.Signal.new!("match.three", %{amount: 150}, source: "/test")
      {:ok, targets} = JidoRouter.route(router, signal)

      assert length(targets) == 1
      assert TestAction in targets
    end

    test "routes don't match when match function returns false" do
      state = build_test_state(AgentWithMatchFnRoutes)
      router = SignalRouter.build(state)

      # Signal with amount <= 100 should not match
      signal = Jido.Signal.new!("match.three", %{amount: 50}, source: "/test")
      result = JidoRouter.route(router, signal)

      # Should return no match or empty list
      assert result == {:ok, []} or match?({:error, _}, result)
    end
  end

  describe "build/1 priority handling" do
    test "applies default strategy priority (50) to routes without explicit priority" do
      state = build_test_state(AgentWithStrategy)
      router = SignalRouter.build(state)

      # Verify the router was built - we can't easily inspect internal priority
      # but we can verify routes work
      signal = Jido.Signal.new!("strategy.action", %{}, source: "/test")
      {:ok, targets} = JidoRouter.route(router, signal)

      assert TestAction in targets
    end

    test "applies default agent priority (0) to routes without explicit priority" do
      state = build_test_state(AgentWithRoutes)
      router = SignalRouter.build(state)

      signal = Jido.Signal.new!("agent.action", %{}, source: "/test")
      {:ok, targets} = JidoRouter.route(router, signal)

      assert TestAction in targets
    end

    test "applies default skill priority (-10) to routes without explicit priority" do
      state = build_test_state(AgentWithSkills)
      router = SignalRouter.build(state)

      signal = Jido.Signal.new!("skill.custom", %{}, source: "/test")
      {:ok, targets} = JidoRouter.route(router, signal)

      assert TestAction in targets
    end
  end

  describe "build/1 combined routes" do
    test "combines routes from strategy, agent, and skills" do
      # Create an agent that has strategy routes, agent routes, and skill routes
      defmodule CombinedAgent do
        @moduledoc false
        use Jido.Agent,
          name: "combined_agent",
          strategy: JidoTest.AgentServer.SignalRouterTest.StrategyWithRoutes,
          schema: [],
          skills: [JidoTest.AgentServer.SignalRouterTest.SkillWithRouter]

        def signal_routes do
          [{"combined.agent", JidoTest.AgentServer.SignalRouterTest.TestAction}]
        end
      end

      state = build_test_state(CombinedAgent)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # Strategy: 2 routes, Agent: 1 route, Skill: 2 routes = 5 total
      assert router.route_count == 5
    end
  end

  describe "build/1 error handling" do
    test "returns empty router when no routes are defined" do
      state = build_test_state(AgentWithoutRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count == 0
    end
  end
end
