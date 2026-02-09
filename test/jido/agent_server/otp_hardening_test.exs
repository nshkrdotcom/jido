defmodule JidoTest.AgentServer.OTPHardeningTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal

  defmodule PingAction do
    @moduledoc false
    use Jido.Action, name: "otp_hardening_ping", schema: []

    def run(_params, context) do
      count = Map.get(context.agent.state, :ping_count, 0) + 1
      {:ok, %{ping_count: count}}
    end
  end

  defmodule ScheduleProbeAction do
    @moduledoc false
    use Jido.Action, name: "otp_hardening_schedule_probe", schema: []

    def run(_params, _context) do
      signal = Signal.new!("probe.tick", %{}, source: "/test/otp_hardening")
      {:ok, %{}, [%Directive.Schedule{delay_ms: 200, message: signal}]}
    end
  end

  defmodule ProbeTickAction do
    @moduledoc false
    use Jido.Action, name: "otp_hardening_probe_tick", schema: []

    def run(_params, context) do
      if is_pid(context.agent.state.test_pid) do
        send(context.agent.state.test_pid, :probe_tick)
      end

      ticks = Map.get(context.agent.state, :probe_ticks, 0) + 1
      {:ok, %{probe_ticks: ticks}}
    end
  end

  defmodule LinkedChildPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "otp_hardening_linked_child_plugin",
      state_key: :otp_hardening,
      actions: [
        JidoTest.AgentServer.OTPHardeningTest.PingAction,
        JidoTest.AgentServer.OTPHardeningTest.ScheduleProbeAction,
        JidoTest.AgentServer.OTPHardeningTest.ProbeTickAction
      ]

    @impl Jido.Plugin
    def child_spec(_config) do
      %{
        id: __MODULE__,
        start: {Agent, :start_link, [fn -> :otp_hardening_child end]}
      }
    end
  end

  defmodule OTPHardeningAgent do
    @moduledoc false
    use Jido.Agent,
      name: "otp_hardening_agent",
      schema: [
        ping_count: [type: :integer, default: 0],
        probe_ticks: [type: :integer, default: 0],
        test_pid: [type: :any, default: nil]
      ],
      plugins: [JidoTest.AgentServer.OTPHardeningTest.LinkedChildPlugin]

    def signal_routes(_ctx) do
      [
        {"ping", PingAction},
        {"schedule_probe", ScheduleProbeAction},
        {"probe.tick", ProbeTickAction}
      ]
    end
  end

  describe "linked child crash hardening" do
    test "AgentServer survives linked plugin child crash", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(agent: OTPHardeningAgent, id: "otp-crash-test", jido: jido)

      child_pid = plugin_child_pid(pid)
      child_ref = Process.monitor(child_pid)

      Process.exit(child_pid, :boom)
      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, :boom}, 1_000

      eventually(fn ->
        {:ok, state} = AgentServer.state(pid)
        map_size(state.children) == 0
      end)

      assert Process.alive?(pid)
      assert {:ok, _state} = AgentServer.state(pid)
      assert :ok = AgentServer.cast(pid, Signal.new!("ping", %{}, source: "/test"))

      GenServer.stop(pid)
    end
  end

  describe "terminate cleanup hardening" do
    test "stopping AgentServer cleans up children and pending scheduled work", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(
          agent: OTPHardeningAgent,
          id: "otp-terminate-test",
          initial_state: %{test_pid: self()},
          jido: jido
        )

      child_pid = plugin_child_pid(pid)
      child_ref = Process.monitor(child_pid)

      schedule_signal = Signal.new!("schedule_probe", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, schedule_signal)

      eventually_state(pid, fn state ->
        map_size(state.scheduled_timers) > 0
      end)

      GenServer.stop(pid)

      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, _reason}, 1_000
      refute_receive :probe_tick, 300
    end
  end

  defp plugin_child_pid(agent_server_pid) do
    eventually(fn ->
      with {:ok, state} <- AgentServer.state(agent_server_pid),
           [%{pid: pid} | _] when is_pid(pid) <- Map.values(state.children) do
        pid
      else
        _ -> false
      end
    end)
  end
end
