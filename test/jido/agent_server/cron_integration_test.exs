defmodule JidoTest.AgentServer.CronIntegrationTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag capture_log: true

  alias Jido.AgentServer
  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule CronCountAction do
    @moduledoc false
    use Jido.Action, name: "cron_count", schema: []

    def run(params, context) do
      count = Map.get(context.state, :tick_count, 0)
      ticks = Map.get(context.state, :ticks, [])
      {:ok, %{tick_count: count + 1, ticks: ticks ++ [params]}}
    end
  end

  defmodule RegisterCronAction do
    @moduledoc false
    use Jido.Action, name: "register_cron", schema: []

    def run(params, _context) do
      cron_expr = Map.get(params, :cron)
      job_id = Map.get(params, :job_id)
      message = Map.get(params, :message, Signal.new!(%{type: "cron.tick", source: "/test"}))
      timezone = Map.get(params, :timezone)

      directive = Directive.cron(cron_expr, message, job_id: job_id, timezone: timezone)
      {:ok, %{}, [directive]}
    end
  end

  defmodule CancelCronAction do
    @moduledoc false
    use Jido.Action, name: "cancel_cron", schema: []

    def run(%{job_id: job_id}, _context) do
      {:ok, %{}, [Directive.cron_cancel(job_id)]}
    end
  end

  defmodule CronTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "cron_test_agent",
      schema: [
        tick_count: [type: :integer, default: 0],
        ticks: [type: {:list, :any}, default: []]
      ]

    def signal_routes do
      [
        {"register_cron", RegisterCronAction},
        {"cancel_cron", CancelCronAction},
        {"cron.tick", CronCountAction}
      ]
    end
  end

  setup do
    :ok
  end

  describe "cron job registration" do
    test "agent can register a cron job" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-1")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :heartbeat,
            cron: "* * * * *"
          }
        })

      :ok = AgentServer.cast("cron-test-1", register_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-1")
      assert Map.has_key?(state.cron_jobs, :heartbeat)

      job_name = state.cron_jobs[:heartbeat]
      assert is_binary(job_name)
      assert String.contains?(job_name, "jido_cron:cron-test-1:")

      GenServer.stop(pid)
    end

    test "agent can register multiple cron jobs" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-2")

      for {job_id, cron_expr} <- [heartbeat: "* * * * *", daily: "@daily", hourly: "@hourly"] do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: job_id, cron: cron_expr}
          })

        :ok = AgentServer.cast("cron-test-2", register_signal)
      end

      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-2")
      assert map_size(state.cron_jobs) == 3
      assert Map.has_key?(state.cron_jobs, :heartbeat)
      assert Map.has_key?(state.cron_jobs, :daily)
      assert Map.has_key?(state.cron_jobs, :hourly)

      GenServer.stop(pid)
    end

    test "registering same job_id updates existing job (upsert)" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-3")

      register_signal1 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :updatable, cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-3", register_signal1)
      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-3")
      first_job_name = state1.cron_jobs[:updatable]

      register_signal2 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :updatable, cron: "@hourly"}
        })

      :ok = AgentServer.cast("cron-test-3", register_signal2)
      Process.sleep(100)

      {:ok, state2} = AgentServer.state("cron-test-3")
      assert map_size(state2.cron_jobs) == 1
      second_job_name = state2.cron_jobs[:updatable]
      assert first_job_name == second_job_name

      GenServer.stop(pid)
    end

    test "cron job with timezone" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-4")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :timezone_test,
            cron: "0 9 * * *",
            timezone: "America/New_York"
          }
        })

      :ok = AgentServer.cast("cron-test-4", register_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-4")
      assert Map.has_key?(state.cron_jobs, :timezone_test)

      GenServer.stop(pid)
    end

    test "auto-generates job_id if not provided" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-5")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-5", register_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-5")
      assert map_size(state.cron_jobs) == 1

      [job_id] = Map.keys(state.cron_jobs)
      assert is_reference(job_id)

      GenServer.stop(pid)
    end
  end

  describe "cron job cancellation" do
    test "agent can cancel a cron job" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-6")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :cancellable, cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-6", register_signal)
      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-6")
      assert Map.has_key?(state1.cron_jobs, :cancellable)
      job_name = state1.cron_jobs[:cancellable]

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :cancellable}
        })

      :ok = AgentServer.cast("cron-test-6", cancel_signal)
      Process.sleep(100)

      {:ok, state2} = AgentServer.state("cron-test-6")
      refute Map.has_key?(state2.cron_jobs, :cancellable)

      jobs = Jido.Scheduler.jobs()
      refute Enum.any?(jobs, fn {name, _} -> Atom.to_string(name) == job_name end)

      GenServer.stop(pid)
    end

    test "cancelling non-existent job is safe" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-7")

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :nonexistent}
        })

      :ok = AgentServer.cast("cron-test-7", cancel_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-7")
      assert map_size(state.cron_jobs) == 0

      GenServer.stop(pid)
    end

    test "can cancel and re-register same job_id" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-8")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :toggle, cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-8", register_signal)
      Process.sleep(100)

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :toggle}
        })

      :ok = AgentServer.cast("cron-test-8", cancel_signal)
      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-8")
      refute Map.has_key?(state1.cron_jobs, :toggle)

      register_signal2 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :toggle, cron: "@hourly"}
        })

      :ok = AgentServer.cast("cron-test-8", register_signal2)
      Process.sleep(100)

      {:ok, state2} = AgentServer.state("cron-test-8")
      assert Map.has_key?(state2.cron_jobs, :toggle)
      assert is_binary(state2.cron_jobs[:toggle])

      GenServer.stop(pid)
    end
  end

  describe "cron job execution" do
    test "manually triggering cron job executes action" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-9")

      tick_signal = Signal.new!(%{type: "cron.tick", source: "/scheduler", data: %{tick: 1}})

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :manual_test,
            cron: "* * * * *",
            message: tick_signal
          }
        })

      :ok = AgentServer.cast("cron-test-9", register_signal)
      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-9")
      job_name = state1.cron_jobs[:manual_test]

      :ok = Jido.Scheduler.run_job(String.to_atom(job_name))
      Process.sleep(100)

      {:ok, state2} = AgentServer.state("cron-test-9")
      assert state2.agent.state.tick_count == 1
      assert length(state2.agent.state.ticks) == 1

      :ok = Jido.Scheduler.run_job(String.to_atom(job_name))
      :ok = Jido.Scheduler.run_job(String.to_atom(job_name))
      Process.sleep(100)

      {:ok, state3} = AgentServer.state("cron-test-9")
      assert state3.agent.state.tick_count == 3
      assert length(state3.agent.state.ticks) == 3

      GenServer.stop(pid)
    end
  end

  describe "cleanup on agent termination" do
    test "cron jobs are cleaned up when agent stops normally" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-10")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :cleanup_test, cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-10", register_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-10")
      job_name = state.cron_jobs[:cleanup_test]

      jobs_before = Jido.Scheduler.jobs()
      assert Enum.any?(jobs_before, fn {name, _} -> Atom.to_string(name) == job_name end)

      GenServer.stop(pid)
      Process.sleep(100)

      jobs_after = Jido.Scheduler.jobs()
      refute Enum.any?(jobs_after, fn {name, _} -> Atom.to_string(name) == job_name end)
    end

    test "multiple cron jobs are all cleaned up on termination" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-11")

      job_ids = [:job1, :job2, :job3]

      for job_id <- job_ids do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: job_id, cron: "* * * * *"}
          })

        :ok = AgentServer.cast("cron-test-11", register_signal)
      end

      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-11")
      job_names = Enum.map(job_ids, fn id -> state.cron_jobs[id] end)

      jobs_before = Jido.Scheduler.jobs()

      for job_name <- job_names do
        assert Enum.any?(jobs_before, fn {name, _} -> Atom.to_string(name) == job_name end)
      end

      GenServer.stop(pid)
      Process.sleep(100)

      jobs_after = Jido.Scheduler.jobs()

      for job_name <- job_names do
        refute Enum.any?(jobs_after, fn {name, _} -> Atom.to_string(name) == job_name end)
      end
    end
  end

  describe "job name scoping" do
    test "different agents can use same job_id without collision" do
      {:ok, pid1} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-12a")
      {:ok, pid2} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-12b")

      for agent_id <- ["cron-test-12a", "cron-test-12b"] do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: :shared_name, cron: "* * * * *"}
          })

        :ok = AgentServer.cast(agent_id, register_signal)
      end

      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-12a")
      {:ok, state2} = AgentServer.state("cron-test-12b")

      assert Map.has_key?(state1.cron_jobs, :shared_name)
      assert Map.has_key?(state2.cron_jobs, :shared_name)

      job_name1 = state1.cron_jobs[:shared_name]
      job_name2 = state2.cron_jobs[:shared_name]

      refute job_name1 == job_name2

      jobs = Jido.Scheduler.jobs()
      assert Enum.any?(jobs, fn {name, _} -> Atom.to_string(name) == job_name1 end)
      assert Enum.any?(jobs, fn {name, _} -> Atom.to_string(name) == job_name2 end)

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end
end
