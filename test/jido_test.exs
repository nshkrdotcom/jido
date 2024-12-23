defmodule JidoTest do
  use ExUnit.Case, async: true

  defmodule TestJido do
    use Jido, otp_app: :jido_test_app
  end

  @moduletag :capture_log

  describe "use Jido macro" do
    test "child_spec can be started under a supervisor" do
      # Set some config for :jido_test_app, TestJido
      Application.put_env(:jido_test_app, TestJido, name: TestJido)

      # Start the supervised instance
      {:ok, sup} = start_supervised(TestJido)

      # Verify it started a supervisor with the correct name
      assert Process.alive?(sup)
      # Could also check that the registry is started:
      registry_name = Module.concat(TestJido, "Registry")
      assert Process.whereis(registry_name)

      # or check dynamic supervisor
      dsup_name = Module.concat(TestJido, "AgentSupervisor")
      assert Process.whereis(dsup_name)
    end

    test "config is loaded from application env" do
      Application.put_env(:jido_test_app, TestJido, pubsub: "FakePubSub")
      assert TestJido.config()[:pubsub] == "FakePubSub"
    end
  end

  describe "get_agent_by_id" do
    setup context do
      test_name = context.test
      pubsub_name = Module.concat(TestJido, "#{test_name}.PubSub")
      registry_name = Module.concat(TestJido, "#{test_name}.Registry")

      {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})
      {:ok, _} = start_supervised({Registry, keys: :unique, name: registry_name})

      # Temporarily override the Jido.AgentRegistry name for this test
      Application.put_env(:jido, :agent_registry, registry_name)
      on_exit(fn -> Application.delete_env(:jido, :agent_registry) end)

      {:ok, pubsub: pubsub_name, registry: registry_name}
    end

    test "returns the pid of an existing agent", %{pubsub: pubsub} do
      # Set up test agent using BasicAgent from test_agent.ex
      agent = JidoTest.TestAgents.BasicAgent.new("test_agent")
      {:ok, runtime} = Jido.Agent.Runtime.start_link(agent: agent, pubsub: pubsub)

      # Look up the agent by ID
      assert {:ok, pid} = Jido.get_agent_by_id("test_agent")
      assert pid == runtime
      assert Process.alive?(pid)
    end

    test "returns error for non-existent agent", %{pubsub: _pubsub} do
      assert {:error, :not_found} = Jido.get_agent_by_id("nonexistent")
    end
  end
end
