defmodule JidoTest.AgentServer.PostInitTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer

  defmodule NoopAction do
    @moduledoc false
    use Jido.Action,
      name: "noop_post_init_action",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule CrashingStartupPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "crashing_startup_plugin",
      state_key: :crashing_startup,
      actions: [JidoTest.AgentServer.PostInitTest.NoopAction]

    @impl Jido.Plugin
    def child_spec(_config) do
      raise "intentional child_spec crash during post_init"
    end
  end

  defmodule HealthyStartupPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "healthy_startup_plugin",
      state_key: :healthy_startup,
      actions: [JidoTest.AgentServer.PostInitTest.NoopAction]

    @impl Jido.Plugin
    def child_spec(_config) do
      %{
        id: {__MODULE__, :healthy_worker},
        start: {Agent, :start_link, [fn -> :ok end]}
      }
    end
  end

  defmodule MixedStartupAgent do
    @moduledoc false
    use Jido.Agent,
      name: "mixed_startup_agent",
      plugins: [
        JidoTest.AgentServer.PostInitTest.CrashingStartupPlugin,
        JidoTest.AgentServer.PostInitTest.HealthyStartupPlugin
      ]
  end

  describe "post_init readiness hardening" do
    test "plugin child_spec crash is isolated and startup finalizes", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: MixedStartupAgent, jido: jido)

      eventually_state(pid, fn state ->
        state.status == :idle and map_size(state.children) == 1
      end)

      {:ok, state} = AgentServer.state(pid)

      assert Process.alive?(pid)
      assert state.status == :idle
      assert map_size(state.children) == 1

      [{{:plugin, plugin_module, _}, _child_info}] = Map.to_list(state.children)
      assert plugin_module == JidoTest.AgentServer.PostInitTest.HealthyStartupPlugin

      GenServer.stop(pid)
    end
  end
end
