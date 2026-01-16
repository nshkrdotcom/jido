defmodule JidoTest.Skill.RoutesTest do
  use ExUnit.Case, async: true

  alias Jido.Skill.Routes
  alias Jido.Skill.Instance

  defmodule TestAction1 do
    @moduledoc false
    use Jido.Action,
      name: "test_action_1",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule TestAction2 do
    @moduledoc false
    use Jido.Action,
      name: "test_action_2",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule TestAction3 do
    @moduledoc false
    use Jido.Action,
      name: "test_action_3",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule SkillWithRoutes do
    @moduledoc false
    use Jido.Skill,
      name: "skill_with_routes",
      state_key: :skill_routes,
      actions: [TestAction1, TestAction2],
      routes: [
        {"post", TestAction1},
        {"list", TestAction2}
      ]
  end

  defmodule SkillWithRoutesAndOptions do
    @moduledoc false
    use Jido.Skill,
      name: "skill_with_opts",
      state_key: :skill_opts,
      actions: [TestAction1, TestAction2],
      routes: [
        {"post", TestAction1, priority: 5},
        {"list", TestAction2, on_conflict: :replace}
      ]
  end

  defmodule SkillWithPatterns do
    @moduledoc false
    use Jido.Skill,
      name: "skill_with_patterns",
      state_key: :skill_patterns,
      actions: [TestAction1],
      signal_patterns: ["incoming.*"]
  end

  defmodule SkillNoRoutes do
    @moduledoc false
    use Jido.Skill,
      name: "skill_no_routes",
      state_key: :skill_no_routes,
      actions: [TestAction1]
  end

  describe "expand_routes/1" do
    test "expands routes with prefix from instance" do
      instance = Instance.new(SkillWithRoutes)

      routes = Routes.expand_routes(instance)

      assert length(routes) == 2
      assert {"skill_with_routes.post", TestAction1, []} in routes
      assert {"skill_with_routes.list", TestAction2, []} in routes
    end

    test "preserves route options" do
      instance = Instance.new(SkillWithRoutesAndOptions)

      routes = Routes.expand_routes(instance)

      assert length(routes) == 2
      assert {"skill_with_opts.post", TestAction1, [priority: 5]} in routes
      assert {"skill_with_opts.list", TestAction2, [on_conflict: :replace]} in routes
    end

    test "applies alias prefix when using :as option" do
      instance = Instance.new({SkillWithRoutes, as: :support})

      routes = Routes.expand_routes(instance)

      assert length(routes) == 2
      assert {"support.skill_with_routes.post", TestAction1, []} in routes
      assert {"support.skill_with_routes.list", TestAction2, []} in routes
    end

    test "falls back to legacy signal_patterns when routes empty" do
      instance = Instance.new(SkillWithPatterns)

      routes = Routes.expand_routes(instance)

      assert length(routes) == 1
      assert {"skill_with_patterns.incoming.*", TestAction1, []} in routes
    end

    test "returns empty list when no routes and no patterns" do
      instance = Instance.new(SkillNoRoutes)

      routes = Routes.expand_routes(instance)

      assert routes == []
    end

    test "legacy patterns generate routes for each action" do
      defmodule MultiActionPatternSkill do
        @moduledoc false
        use Jido.Skill,
          name: "multi_action",
          state_key: :multi_action,
          actions: [TestAction1, TestAction2],
          signal_patterns: ["pattern1"]
      end

      instance = Instance.new(MultiActionPatternSkill)

      routes = Routes.expand_routes(instance)

      assert length(routes) == 2
      assert {"multi_action.pattern1", TestAction1, []} in routes
      assert {"multi_action.pattern1", TestAction2, []} in routes
    end

    test "returns empty when skill has custom router/1 callback" do
      defmodule SkillWithCustomRouter do
        @moduledoc false
        use Jido.Skill,
          name: "custom_router",
          state_key: :custom_router,
          actions: [TestAction1],
          signal_patterns: ["ignored.*"]

        @impl Jido.Skill
        def router(_config) do
          [{"custom.route", TestAction1}]
        end
      end

      instance = Instance.new(SkillWithCustomRouter)

      routes = Routes.expand_routes(instance)

      assert routes == []
    end

    test "falls back to patterns when router/1 returns nil" do
      defmodule SkillWithNilRouter do
        @moduledoc false
        use Jido.Skill,
          name: "nil_router",
          state_key: :nil_router,
          actions: [TestAction1],
          signal_patterns: ["fallback.*"]

        @impl Jido.Skill
        def router(_config), do: nil
      end

      instance = Instance.new(SkillWithNilRouter)

      routes = Routes.expand_routes(instance)

      assert length(routes) == 1
      assert {"nil_router.fallback.*", TestAction1, []} in routes
    end
  end

  describe "detect_conflicts/1" do
    test "returns ok when no conflicts" do
      routes = [
        {"slack.post", TestAction1, []},
        {"slack.list", TestAction2, []}
      ]

      assert {:ok, merged} = Routes.detect_conflicts(routes)
      assert length(merged) == 2
      assert {"slack.post", TestAction1, -10} in merged
      assert {"slack.list", TestAction2, -10} in merged
    end

    test "returns error when same path with same priority" do
      routes = [
        {"slack.post", TestAction1, []},
        {"slack.post", TestAction2, []}
      ]

      assert {:error, conflicts} = Routes.detect_conflicts(routes)
      assert length(conflicts) == 1
      assert hd(conflicts) =~ "Route conflict: 'slack.post'"
      assert hd(conflicts) =~ "same priority -10"
    end

    test "higher priority wins when different priorities" do
      routes = [
        {"slack.post", TestAction1, [priority: -10]},
        {"slack.post", TestAction2, [priority: 5]}
      ]

      assert {:ok, merged} = Routes.detect_conflicts(routes)
      assert length(merged) == 1
      assert {"slack.post", TestAction2, 5} in merged
    end

    test "on_conflict: :replace bypasses conflict error" do
      routes = [
        {"slack.post", TestAction1, []},
        {"slack.post", TestAction2, [on_conflict: :replace]}
      ]

      assert {:ok, merged} = Routes.detect_conflicts(routes)
      assert length(merged) == 1
      assert {"slack.post", TestAction2, -10} in merged
    end

    test "on_conflict: :replace with higher priority wins" do
      routes = [
        {"slack.post", TestAction1, [priority: 5, on_conflict: :replace]},
        {"slack.post", TestAction2, [on_conflict: :replace]}
      ]

      assert {:ok, merged} = Routes.detect_conflicts(routes)
      assert length(merged) == 1
      assert {"slack.post", TestAction1, 5} in merged
    end

    test "multiple conflicts are all reported" do
      routes = [
        {"slack.post", TestAction1, []},
        {"slack.post", TestAction2, []},
        {"slack.list", TestAction1, []},
        {"slack.list", TestAction3, []}
      ]

      assert {:error, conflicts} = Routes.detect_conflicts(routes)
      assert length(conflicts) == 2
      assert Enum.any?(conflicts, &(&1 =~ "'slack.post'"))
      assert Enum.any?(conflicts, &(&1 =~ "'slack.list'"))
    end

    test "applies default priority of -10" do
      routes = [{"slack.post", TestAction1, []}]

      assert {:ok, [{"slack.post", TestAction1, -10}]} = Routes.detect_conflicts(routes)
    end

    test "explicit priority overrides default" do
      routes = [{"slack.post", TestAction1, [priority: 0]}]

      assert {:ok, [{"slack.post", TestAction1, 0}]} = Routes.detect_conflicts(routes)
    end
  end

  describe "default_priority/0" do
    test "returns -10" do
      assert Routes.default_priority() == -10
    end
  end

  describe "integration: expand and detect" do
    test "two instances of same skill with different :as don't conflict" do
      support = Instance.new({SkillWithRoutes, as: :support})
      sales = Instance.new({SkillWithRoutes, as: :sales})

      support_routes = Routes.expand_routes(support)
      sales_routes = Routes.expand_routes(sales)

      all_routes = support_routes ++ sales_routes

      assert {:ok, merged} = Routes.detect_conflicts(all_routes)
      assert length(merged) == 4
    end

    test "same skill without :as conflicts with itself" do
      instance1 = Instance.new(SkillWithRoutes)
      instance2 = Instance.new(SkillWithRoutes)

      routes1 = Routes.expand_routes(instance1)
      routes2 = Routes.expand_routes(instance2)

      all_routes = routes1 ++ routes2

      assert {:error, conflicts} = Routes.detect_conflicts(all_routes)
      assert length(conflicts) == 2
    end
  end
end
