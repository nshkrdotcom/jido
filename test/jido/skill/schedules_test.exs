defmodule JidoTest.Skill.SchedulesTest do
  use ExUnit.Case, async: true

  alias Jido.Skill.Schedules
  alias Jido.Skill.Instance

  defmodule RefreshTokenAction do
    @moduledoc false
    use Jido.Action,
      name: "refresh_token",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule DailyDigestAction do
    @moduledoc false
    use Jido.Action,
      name: "daily_digest",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule CleanupAction do
    @moduledoc false
    use Jido.Action,
      name: "cleanup",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule SkillWithSchedules do
    @moduledoc false
    use Jido.Skill,
      name: "scheduled_skill",
      state_key: :scheduled,
      actions: [RefreshTokenAction, DailyDigestAction],
      schedules: [
        {"*/5 * * * *", RefreshTokenAction},
        {"0 9 * * 1-5", DailyDigestAction, tz: "America/New_York"}
      ]
  end

  defmodule SkillWithCustomSignal do
    @moduledoc false
    use Jido.Skill,
      name: "custom_signal_skill",
      state_key: :custom_signal,
      actions: [CleanupAction],
      schedules: [
        {"0 0 * * *", CleanupAction, signal: "maintenance.cleanup"}
      ]
  end

  defmodule SkillNoSchedules do
    @moduledoc false
    use Jido.Skill,
      name: "no_schedules",
      state_key: :no_schedules,
      actions: [RefreshTokenAction]
  end

  describe "expand_schedules/1" do
    test "expands simple schedule with default timezone" do
      instance = Instance.new(SkillWithSchedules)
      schedules = Schedules.expand_schedules(instance)

      assert length(schedules) == 2

      refresh_spec = Enum.find(schedules, &(&1.action == RefreshTokenAction))
      assert refresh_spec.cron_expression == "*/5 * * * *"
      assert refresh_spec.job_id == {:skill_schedule, :scheduled, RefreshTokenAction}
      assert refresh_spec.signal_type == "scheduled_skill.__schedule__.refresh_token_action"
      assert refresh_spec.timezone == "Etc/UTC"
    end

    test "expands schedule with custom timezone" do
      instance = Instance.new(SkillWithSchedules)
      schedules = Schedules.expand_schedules(instance)

      digest_spec = Enum.find(schedules, &(&1.action == DailyDigestAction))
      assert digest_spec.cron_expression == "0 9 * * 1-5"
      assert digest_spec.job_id == {:skill_schedule, :scheduled, DailyDigestAction}
      assert digest_spec.signal_type == "scheduled_skill.__schedule__.daily_digest_action"
      assert digest_spec.timezone == "America/New_York"
    end

    test "expands schedule with custom signal type" do
      instance = Instance.new(SkillWithCustomSignal)
      schedules = Schedules.expand_schedules(instance)

      assert length(schedules) == 1
      [spec] = schedules
      assert spec.cron_expression == "0 0 * * *"
      assert spec.job_id == {:skill_schedule, :custom_signal, CleanupAction}
      assert spec.signal_type == "custom_signal_skill.maintenance.cleanup"
      assert spec.timezone == "Etc/UTC"
    end

    test "returns empty list for skill without schedules" do
      instance = Instance.new(SkillNoSchedules)
      schedules = Schedules.expand_schedules(instance)

      assert schedules == []
    end

    test "applies alias to job_id when using :as option" do
      instance = Instance.new({SkillWithSchedules, as: :support})
      schedules = Schedules.expand_schedules(instance)

      refresh_spec = Enum.find(schedules, &(&1.action == RefreshTokenAction))
      assert refresh_spec.job_id == {:skill_schedule, :scheduled_support, RefreshTokenAction}
    end

    test "applies alias to signal_type when using :as option" do
      instance = Instance.new({SkillWithSchedules, as: :support})
      schedules = Schedules.expand_schedules(instance)

      refresh_spec = Enum.find(schedules, &(&1.action == RefreshTokenAction))

      assert refresh_spec.signal_type ==
               "support.scheduled_skill.__schedule__.refresh_token_action"
    end
  end

  describe "schedule_routes/1" do
    test "generates routes for schedule signal types" do
      instance = Instance.new(SkillWithSchedules)
      routes = Schedules.schedule_routes(instance)

      assert length(routes) == 2

      refresh_route =
        Enum.find(routes, fn {signal_type, _, _} ->
          String.contains?(signal_type, "refresh_token")
        end)

      {signal_type, action, opts} = refresh_route
      assert signal_type == "scheduled_skill.__schedule__.refresh_token_action"
      assert action == RefreshTokenAction
      assert opts[:priority] == Schedules.schedule_route_priority()
    end

    test "returns empty list for skill without schedules" do
      instance = Instance.new(SkillNoSchedules)
      routes = Schedules.schedule_routes(instance)

      assert routes == []
    end

    test "applies alias prefix to routes when using :as option" do
      instance = Instance.new({SkillWithSchedules, as: :sales})
      routes = Schedules.schedule_routes(instance)

      assert length(routes) == 2

      signal_types = Enum.map(routes, fn {signal_type, _, _} -> signal_type end)
      assert "sales.scheduled_skill.__schedule__.refresh_token_action" in signal_types
      assert "sales.scheduled_skill.__schedule__.daily_digest_action" in signal_types
    end
  end

  describe "schedule_route_priority/0" do
    test "returns a negative priority lower than default skill routes" do
      priority = Schedules.schedule_route_priority()
      default_priority = Jido.Skill.Routes.default_priority()

      assert priority < default_priority
      assert priority == -20
    end
  end

  describe "job_id uniqueness" do
    test "different skill instances have different job_ids" do
      support = Instance.new({SkillWithSchedules, as: :support})
      sales = Instance.new({SkillWithSchedules, as: :sales})

      support_schedules = Schedules.expand_schedules(support)
      sales_schedules = Schedules.expand_schedules(sales)

      support_job_ids = Enum.map(support_schedules, & &1.job_id)
      sales_job_ids = Enum.map(sales_schedules, & &1.job_id)

      assert support_job_ids != sales_job_ids

      support_refresh = Enum.find(support_schedules, &(&1.action == RefreshTokenAction))
      sales_refresh = Enum.find(sales_schedules, &(&1.action == RefreshTokenAction))

      assert support_refresh.job_id == {:skill_schedule, :scheduled_support, RefreshTokenAction}
      assert sales_refresh.job_id == {:skill_schedule, :scheduled_sales, RefreshTokenAction}
    end

    test "same skill without alias has consistent job_id" do
      instance1 = Instance.new(SkillWithSchedules)
      instance2 = Instance.new(SkillWithSchedules)

      schedules1 = Schedules.expand_schedules(instance1)
      schedules2 = Schedules.expand_schedules(instance2)

      job_ids1 = Enum.map(schedules1, & &1.job_id) |> Enum.sort()
      job_ids2 = Enum.map(schedules2, & &1.job_id) |> Enum.sort()

      assert job_ids1 == job_ids2
    end
  end
end
