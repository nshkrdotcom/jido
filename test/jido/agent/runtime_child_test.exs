defmodule Jido.Agent.RuntimeChildTest do
  use ExUnit.Case, async: true
  require Logger
  import ExUnit.CaptureLog

  alias Jido.Agent.Runtime
  alias JidoTest.TestAgents.SimpleAgent

  setup do
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    agent = SimpleAgent.new("test_agent")
    {:ok, runtime} = start_supervised({Runtime, agent: agent, pubsub: TestPubSub})
    %{runtime: runtime}
  end

  describe "start_process/2" do
    test "starts a child process", %{runtime: runtime} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      assert {:ok, pid} = Runtime.start_process(runtime, child_spec)
      assert Process.alive?(pid)
    end

    test "fails to start invalid child spec", %{runtime: runtime} do
      invalid_spec = %{
        id: :invalid_child,
        start: {:not_a_module, :not_a_function, []}
      }

      capture_log(fn ->
        assert {:error, _reason} = Runtime.start_process(runtime, invalid_spec)
      end)
    end
  end

  describe "list_processes/1" do
    test "lists running child processes", %{runtime: runtime} do
      # Start a few test processes
      child_spec1 = %{
        id: :test_child1,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      child_spec2 = %{
        id: :test_child2,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, pid1} = Runtime.start_process(runtime, child_spec1)
      {:ok, pid2} = Runtime.start_process(runtime, child_spec2)

      assert {:ok, children} = Runtime.list_processes(runtime)
      assert length(children) == 2

      pids = Enum.map(children, fn {:undefined, pid, :worker, _} -> pid end)
      assert pid1 in pids
      assert pid2 in pids
    end

    test "returns empty list when no children", %{runtime: runtime} do
      assert {:ok, children} = Runtime.list_processes(runtime)
      assert children == []
    end
  end

  describe "terminate_process/2" do
    test "terminates a child process", %{runtime: runtime} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, pid} = Runtime.start_process(runtime, child_spec)
      assert Process.alive?(pid)

      assert :ok = Runtime.terminate_process(runtime, pid)
      refute Process.alive?(pid)

      {:ok, children} = Runtime.list_processes(runtime)
      refute Enum.any?(children, fn {child_pid, _} -> child_pid == pid end)
    end

    test "fails to terminate non-existent process", %{runtime: runtime} do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)

      capture_log(fn ->
        assert {:error, :not_found} = Runtime.terminate_process(runtime, non_existent_pid)
      end)
    end
  end

  describe "child process cleanup" do
    test "kills child processes when runtime is terminated", %{runtime: runtime} do
      # Start a few child processes
      child_spec1 = %{
        id: :test_child1,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      child_spec2 = %{
        id: :test_child2,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, pid1} = Runtime.start_process(runtime, child_spec1)
      {:ok, pid2} = Runtime.start_process(runtime, child_spec2)

      # Verify processes are running
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      # Stop the runtime using the supervisor
      stop_supervised(Runtime)

      # Give processes time to shut down
      Process.sleep(100)

      # Verify child processes were killed
      refute Process.alive?(pid1)
      refute Process.alive?(pid2)
    end
  end
end
