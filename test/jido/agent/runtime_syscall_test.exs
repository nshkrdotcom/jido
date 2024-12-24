defmodule Jido.Agent.Runtime.SyscallTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Runtime.{Syscall, State}
  alias JidoTest.TestAgents.SimpleAgent

  setup do
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = SimpleAgent.new("test")
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})

    state = %State{
      agent: agent,
      child_supervisor: supervisor,
      pubsub: TestPubSub,
      topic: "test_topic",
      status: :idle,
      pending: :queue.new()
    }

    {:ok, state: state}
  end

  describe "process management syscalls" do
    test "spawn creates a new child process", %{state: state} do
      task = fn -> Process.sleep(1000) end
      {result, new_state} = Syscall.execute(state, {:spawn, {:task, task}})
      assert {:ok, pid} = result
      assert Process.alive?(pid)
      assert state == new_state
    end

    test "kill terminates a specific process", %{state: state} do
      task = fn -> Process.sleep(1000) end
      {{:ok, pid}, state} = Syscall.execute(state, {:spawn, {:task, task}})
      assert Process.alive?(pid)

      {result, new_state} = Syscall.execute(state, {:kill, pid})
      assert result == :ok
      refute Process.alive?(pid)
      assert state == new_state
    end

    test "kill_all terminates all child processes", %{state: state} do
      task = fn -> Process.sleep(1000) end
      {{:ok, pid1}, state} = Syscall.execute(state, {:spawn, {:task, task}})
      {{:ok, pid2}, state} = Syscall.execute(state, {:spawn, {:task, task}})

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      {result, new_state} = Syscall.execute(state, {:kill_all})
      assert result == :ok
      refute Process.alive?(pid1)
      refute Process.alive?(pid2)
      assert state == new_state
    end
  end

  describe "command queue syscalls" do
    test "enqueue adds command to pending queue", %{state: state} do
      cmd = :test_cmd
      params = %{key: "value"}
      {result, new_state} = Syscall.execute(state, {:enqueue, cmd, params})
      assert result == :ok
      assert :queue.len(new_state.pending) == 1
    end

    test "reset_queue clears pending commands", %{state: state} do
      {:ok, state} = Syscall.execute(state, {:enqueue, :cmd1, %{}})
      {:ok, state} = Syscall.execute(state, {:enqueue, :cmd2, %{}})
      assert :queue.len(state.pending) == 2

      {result, new_state} = Syscall.execute(state, :reset_queue)
      assert result == :ok
      assert :queue.is_empty(new_state.pending)
    end

    test "pause transitions running state to paused", %{state: state} do
      state = %{state | status: :running}
      {result, new_state} = Syscall.execute(state, :pause)
      assert result == :ok
      assert new_state.status == :paused
    end

    test "resume transitions paused state to idle", %{state: state} do
      state = %{state | status: :paused}
      {result, new_state} = Syscall.execute(state, :resume)
      assert result == :ok
      assert new_state.status == :idle
    end
  end

  describe "pubsub syscalls" do
    test "subscribe adds subscription", %{state: state} do
      {result, new_state} = Syscall.execute(state, {:subscribe, :test_topic})
      assert result == :ok
      assert state == new_state
    end

    test "unsubscribe removes subscription", %{state: state} do
      {:ok, state} = Syscall.execute(state, {:subscribe, :test_topic})
      {result, new_state} = Syscall.execute(state, {:unsubscribe, :test_topic})
      assert result == :ok
      assert state == new_state
    end
  end

  describe "error handling" do
    test "returns error for invalid syscall", %{state: state} do
      {result, new_state} = Syscall.execute(state, {:invalid_syscall, []})
      assert result == {:error, :invalid_syscall}
      assert state == new_state
    end

    test "handles process not found errors", %{state: state} do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)

      {result, new_state} = Syscall.execute(state, {:kill, non_existent_pid})
      assert result == {:error, :not_found}
      assert state == new_state
    end
  end
end
