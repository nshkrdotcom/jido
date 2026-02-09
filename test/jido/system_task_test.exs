defmodule JidoTest.SystemTaskTest do
  use ExUnit.Case, async: false

  alias Jido.SystemTask

  describe "async_nolink/1" do
    test "runs under Jido.SystemTaskSupervisor when available" do
      assert is_pid(Process.whereis(Jido.SystemTaskSupervisor))
      parent = self()

      task =
        SystemTask.async_nolink(fn ->
          send(parent, {:task_started, self()})

          receive do
            :release -> :ok
          end
        end)

      assert %Task{} = task
      assert_receive {:task_started, task_pid}, 500
      assert task_pid == task.pid
      assert task.pid in Task.Supervisor.children(Jido.SystemTaskSupervisor)

      links = Process.info(self(), :links) |> elem(1)
      refute task.pid in links

      send(task.pid, :release)
      assert :ok = Task.await(task)
    end
  end

  describe "fallback behavior" do
    test "async_nolink/2 falls back when supervisor is unavailable" do
      task =
        SystemTask.async_nolink(:jido_missing_system_task_supervisor, fn ->
          :fallback_ok
        end)

      assert %Task{} = task
      assert :fallback_ok = Task.await(task)
    end

    test "start_child/2 falls back when supervisor is unavailable" do
      parent = self()

      pid =
        SystemTask.start_child(:jido_missing_system_task_supervisor, fn ->
          send(parent, :fallback_started)
        end)

      assert is_pid(pid)
      assert_receive :fallback_started, 500
    end
  end
end
