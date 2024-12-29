defmodule JidoTest.Actions.SyscallsTest do
  use ExUnit.Case, async: true

  alias Jido.Actions.Syscall

  alias Jido.Agent.Syscall.{
    SpawnSyscall,
    KillSyscall,
    BroadcastSyscall,
    SubscribeSyscall,
    UnsubscribeSyscall
  }

  describe "Spawn" do
    test "creates a spawn syscall" do
      params = %{module: TestModule, args: [1, 2, 3]}
      assert {:ok, syscall} = Syscall.Spawn.run(params, %{})
      assert %SpawnSyscall{} = syscall
      assert syscall.module == TestModule
      assert syscall.args == [1, 2, 3]
    end
  end

  describe "Kill" do
    test "creates a kill syscall" do
      pid = spawn(fn -> :ok end)
      params = %{pid: pid}
      assert {:ok, syscall} = Syscall.Kill.run(params, %{})
      assert %KillSyscall{} = syscall
      assert syscall.pid == pid
    end
  end

  describe "Broadcast" do
    test "creates a broadcast syscall" do
      params = %{topic: "test_topic", message: "hello world"}
      assert {:ok, syscall} = Syscall.Broadcast.run(params, %{})
      assert %BroadcastSyscall{} = syscall
      assert syscall.topic == "test_topic"
      assert syscall.message == "hello world"
    end
  end

  describe "Subscribe" do
    test "creates a subscribe syscall" do
      params = %{topic: "test_topic"}
      assert {:ok, syscall} = Syscall.Subscribe.run(params, %{})
      assert %SubscribeSyscall{} = syscall
      assert syscall.topic == "test_topic"
    end
  end

  describe "Unsubscribe" do
    test "creates an unsubscribe syscall" do
      params = %{topic: "test_topic"}
      assert {:ok, syscall} = Syscall.Unsubscribe.run(params, %{})
      assert %UnsubscribeSyscall{} = syscall
      assert syscall.topic == "test_topic"
    end
  end
end
