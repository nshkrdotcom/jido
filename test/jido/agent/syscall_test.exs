defmodule JidoTest.Agent.SyscallTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Syscall

  alias Jido.Agent.Syscall.{
    SpawnSyscall,
    KillSyscall,
    BroadcastSyscall,
    SubscribeSyscall,
    UnsubscribeSyscall
  }

  describe "is_syscall?/1" do
    test "returns true for valid syscalls" do
      assert Syscall.is_syscall?(%SpawnSyscall{module: TestModule, args: []})
      assert Syscall.is_syscall?(%KillSyscall{pid: self()})
      assert Syscall.is_syscall?(%BroadcastSyscall{topic: "test", message: "msg"})
      assert Syscall.is_syscall?(%SubscribeSyscall{topic: "test"})
      assert Syscall.is_syscall?(%UnsubscribeSyscall{topic: "test"})
    end

    test "returns false for non-syscalls" do
      refute Syscall.is_syscall?(%{action: :test})
      refute Syscall.is_syscall?(nil)
      refute Syscall.is_syscall?(:not_a_syscall)
    end
  end

  describe "validate_syscall/1" do
    test "validates SpawnSyscall" do
      assert :ok = Syscall.validate_syscall(%SpawnSyscall{module: TestModule, args: []})

      assert {:error, :invalid_module} =
               Syscall.validate_syscall(%SpawnSyscall{module: nil, args: []})
    end

    test "validates KillSyscall" do
      assert :ok = Syscall.validate_syscall(%KillSyscall{pid: self()})
      assert {:error, :invalid_pid} = Syscall.validate_syscall(%KillSyscall{pid: nil})
    end

    test "validates BroadcastSyscall" do
      assert :ok = Syscall.validate_syscall(%BroadcastSyscall{topic: "test", message: "msg"})

      assert {:error, :invalid_topic} =
               Syscall.validate_syscall(%BroadcastSyscall{topic: nil, message: "msg"})
    end

    test "validates SubscribeSyscall" do
      assert :ok = Syscall.validate_syscall(%SubscribeSyscall{topic: "test"})
      assert {:error, :invalid_topic} = Syscall.validate_syscall(%SubscribeSyscall{topic: nil})
    end

    test "validates UnsubscribeSyscall" do
      assert :ok = Syscall.validate_syscall(%UnsubscribeSyscall{topic: "test"})
      assert {:error, :invalid_topic} = Syscall.validate_syscall(%UnsubscribeSyscall{topic: nil})
    end

    test "validates invalid syscalls" do
      assert {:error, :invalid_syscall} = Syscall.validate_syscall(%{not: :syscall})
      assert {:error, :invalid_syscall} = Syscall.validate_syscall(nil)
    end
  end

  describe "edge cases" do
    test "handles syscalls with extra fields" do
      syscall = %SpawnSyscall{module: TestModule, args: []}
      assert Syscall.is_syscall?(syscall)
      assert :ok = Syscall.validate_syscall(syscall)
    end

    test "handles syscalls with invalid field types" do
      syscall = %BroadcastSyscall{topic: 123, message: "msg"}
      assert {:error, :invalid_topic} = Syscall.validate_syscall(syscall)
    end
  end
end
