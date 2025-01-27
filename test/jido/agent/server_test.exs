defmodule JidoTest.Agent.ServerTest do
  use ExUnit.Case, async: true
  alias JidoTest.TestAgents.{BasicAgent, CustomServerAgent}
  alias JidoTest.TestActions.{BasicAction, NoSchema}
  alias Jido.Agent.Server
  import ExUnit.CaptureLog
  require Logger
  @moduletag :capture_log

  setup do
    # Store original log level
    original_level = Logger.level()

    # Configure logger for tests
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: original_level) end)

    # Trap exits in test process to handle process termination
    Process.flag(:trap_exit, true)
    :ok
  end

  describe "BasicAgent GenServer initialization" do
    test "initializes with explicit id" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = BasicAgent.start_link(id: id)
      assert is_pid(pid)
      {:ok, state} = BasicAgent.state(pid)
      assert state.agent.id == id
      assert state.mode == :auto
      assert state.verbose == false
      assert state.max_queue_size == 10_000
      assert state.agent.state.location == :home
      assert state.agent.state.battery_level == 100
    end

    test "initializes with custom schema state" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"

      initial_state = %{
        location: :office,
        battery_level: 75
      }

      {:ok, pid} = BasicAgent.start_link(id: id, initial_state: initial_state)
      {:ok, state} = BasicAgent.state(pid)
      assert state.agent.state.location == :office
      assert state.agent.state.battery_level == 75
    end

    test "initializes with partial schema state" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      initial_state = %{location: :garage}
      {:ok, pid} = BasicAgent.start_link(id: id, initial_state: initial_state)
      assert is_pid(pid)
      {:ok, state} = BasicAgent.state(pid)
      assert state.agent.state.location == :garage
      assert state.agent.state.battery_level == 100
    end

    test "initializes with both schema state and other options" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"

      initial_state = %{
        location: :office,
        battery_level: 60
      }

      {:ok, pid} =
        BasicAgent.start_link(
          id: id,
          initial_state: initial_state,
          verbose: true,
          mode: :manual,
          max_queue_size: 5000
        )

      assert is_pid(pid)
      {:ok, state} = BasicAgent.state(pid)
      assert state.agent.state.location == :office
      assert state.agent.state.battery_level == 60
      assert state.verbose == true
      assert state.mode == :manual
      assert state.max_queue_size == 5000
    end

    test "initializes with verbose mode" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = BasicAgent.start_link(id: id, verbose: true)
      assert is_pid(pid)
      {:ok, state} = BasicAgent.state(pid)
      assert state.verbose == true
    end

    test "initializes with manual mode" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = BasicAgent.start_link(id: id, mode: :manual)
      assert is_pid(pid)
      {:ok, state} = BasicAgent.state(pid)
      assert state.mode == :manual
    end

    test "initializes with custom queue size" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = BasicAgent.start_link(id: id, max_queue_size: 5000)
      assert is_pid(pid)
      {:ok, state} = BasicAgent.state(pid)
      assert state.max_queue_size == 5000
    end

    test "initializes with all custom options" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} =
        BasicAgent.start_link(
          id: id,
          verbose: true,
          mode: :manual,
          max_queue_size: 5000
        )

      assert is_pid(pid)
      {:ok, state} = BasicAgent.state(pid)
      assert state.agent.id == id
      assert state.verbose == true
      assert state.mode == :manual
      assert state.max_queue_size == 5000
    end
  end

  describe "Server direct initialization" do
    test "initializes with agent module" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, name: id)
      assert is_pid(pid)
      state = :sys.get_state(pid)
      assert state.agent.__struct__ == BasicAgent
      assert is_binary(state.agent.id)
      assert state.mode == :auto
      assert state.verbose == false
      assert state.max_queue_size == 10_000
    end

    test "initializes with instantiated agent" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      agent = BasicAgent.new(id: id)
      {:ok, pid} = Server.start_link(agent: agent)
      assert is_pid(pid)
      state = :sys.get_state(pid)
      assert state.agent == agent
      assert state.agent.id == id
    end

    test "initializes with custom dispatch config" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      dispatch = {:bus, [target: :custom, stream: "test_stream"]}
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, dispatch: dispatch)
      assert is_pid(pid)
      state = :sys.get_state(pid)
      assert state.agent.__struct__ == BasicAgent
      assert state.agent.id == id
      assert state.dispatch == dispatch
    end

    test "initializes with custom registry" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Registry.start_link(keys: :unique, name: TestRegistry)
      {:ok, pid} = Server.start_link(agent: BasicAgent, name: id, registry: TestRegistry)
      assert is_pid(pid)
      assert [{^pid, nil}] = Registry.lookup(TestRegistry, id)
    end

    test "fails with invalid agent" do
      assert {:error, :invalid_agent} = Server.start_link(agent: nil)
    end

    test "initializes with all custom options" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      dispatch = {:bus, [target: :custom, stream: "test_stream"]}
      {:ok, _} = Registry.start_link(keys: :unique, name: CustomRegistry)

      {:ok, pid} =
        Server.start_link(
          agent: BasicAgent,
          name: id,
          dispatch: dispatch,
          registry: CustomRegistry,
          verbose: true,
          mode: :manual,
          max_queue_size: 5000
        )

      assert is_pid(pid)
      state = :sys.get_state(pid)
      assert state.agent.__struct__ == BasicAgent
      assert is_binary(state.agent.id)
      assert state.dispatch == dispatch
      assert state.verbose == true
      assert state.mode == :manual
      assert state.max_queue_size == 5000
      assert [{^pid, nil}] = Registry.lookup(CustomRegistry, id)
    end
  end

  describe "BasicAgent GenServer operations" do
    test "set updates state via pid" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = BasicAgent.start_link(id: id, mode: :auto, verbose: true)
      assert is_pid(pid)
      {:ok, state} = BasicAgent.state(pid)
      assert state.verbose == true
      assert state.mode == :auto
      assert state.agent.id == id
    end
  end

  describe "CustomServerAgent lifecycle" do
    test "mount callback is called on initialization" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"

      log =
        capture_log([level: :debug], fn ->
          {:ok, pid} = CustomServerAgent.start_link(id: id)
          ref = Process.monitor(pid)

          # Verify state after mount
          {:ok, state} = CustomServerAgent.state(pid)
          assert state.agent.id == id
          assert state.agent.state.location == :home
          assert state.agent.state.battery_level == 100

          # Clean up and ensure process is fully terminated
          GenServer.stop(pid, :shutdown)
          assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1000

          # Give logger a moment to flush
          Process.sleep(100)
        end)

      # Verify mount was called (the log will contain other debug messages)
      assert log =~ "Mounting CustomServerAgent"
      assert log =~ "Shutting down CustomServerAgent"
    end

    test "shutdown callback is called on termination" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"

      # Start the agent and capture all logs
      log =
        capture_log([level: :debug], fn ->
          {:ok, pid} = CustomServerAgent.start_link(id: id)
          ref = Process.monitor(pid)

          # Send shutdown signal and wait for process to terminate
          GenServer.stop(pid, :shutdown)
          assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1000

          # Give logger a moment to flush
          Process.sleep(100)
        end)

      # Verify both mount and shutdown were called
      assert log =~ "Mounting CustomServerAgent"
      assert log =~ "Shutting down CustomServerAgent"
    end

    test "mount and shutdown handle state correctly" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"
      initial_state = %{location: :office, battery_level: 75}

      log =
        capture_log([level: :debug], fn ->
          {:ok, pid} = CustomServerAgent.start_link(id: id, initial_state: initial_state)
          ref = Process.monitor(pid)

          # Verify state after mount
          {:ok, state} = CustomServerAgent.state(pid)
          assert state.agent.state.location == :office
          assert state.agent.state.battery_level == 75

          # Monitor and capture shutdown
          GenServer.stop(pid, :shutdown)
          assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1000

          # Give logger a moment to flush
          Process.sleep(100)
        end)

      # Verify both callbacks were called
      assert log =~ "Mounting CustomServerAgent"
      assert log =~ "Shutting down CustomServerAgent"
    end

    test "mount failure prevents server start" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"

      # Create an agent with invalid battery level
      agent = CustomServerAgent.new(id)
      agent = %{agent | state: %{agent.state | battery_level: -1}}

      # Attempt to start server and expect failure
      assert {:error, {:mount_failed, :invalid_battery_level}} =
               Jido.Agent.Server.start_link(agent: agent, name: id)
    end

    test "shutdown failure is logged but doesn't prevent termination" do
      id = "test_agent_#{:erlang.unique_integer([:positive])}"

      log =
        capture_log([level: :debug], fn ->
          # Start the agent
          {:ok, pid} = CustomServerAgent.start_link(id: id)
          ref = Process.monitor(pid)

          # Force the agent into a state that will cause shutdown to fail
          :sys.replace_state(pid, fn state ->
            %{state | agent: %{state.agent | state: %{state.agent.state | battery_level: -1}}}
          end)

          # Monitor and capture shutdown
          GenServer.stop(pid, :shutdown)
          assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1000

          # Give logger a moment to flush
          Process.sleep(100)
        end)

      # Verify both mount and shutdown were called
      assert log =~ "Mounting CustomServerAgent"
      assert log =~ "Shutting down CustomServerAgent"
    end
  end
end
