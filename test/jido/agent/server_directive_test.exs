defmodule Jido.Agent.Server.DirectiveTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Server.{Directive, State, Signal}
  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Error

  alias Jido.Agent.Directive.{
    Spawn,
    Kill
  }

  @moduletag :capture_log

  # Helper to compare Error structs ignoring stacktrace
  defp assert_error_match(actual, expected) do
    assert %Error{} = actual
    assert actual.type == expected.type
    assert actual.message == expected.message
    assert actual.details == expected.details
  end

  setup do
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = BasicAgent.new("test")

    state = %State{
      agent: agent,
      child_supervisor: supervisor,
      dispatch: [
        {:pid, [target: self(), delivery_mode: :async]}
      ],
      status: :idle,
      pending_signals: :queue.new()
    }

    {:ok, state: state}
  end

  describe "handle/2" do
    test "processes multiple directives in sequence", %{state: state} do
      task1 = fn -> Process.sleep(1000) end
      task2 = fn -> Process.sleep(1000) end

      directives = [
        %Spawn{module: Task, args: task1},
        %Spawn{module: Task, args: task2}
      ]

      {:ok, new_state} = Directive.handle(state, directives)
      assert state == new_state

      # Verify we received process_started signals for both tasks
      assert_receive {:signal, signal1}
      assert signal1.type == Signal.process_started()
      assert is_pid(signal1.data.child_pid)

      assert_receive {:signal, signal2}
      assert signal2.type == Signal.process_started()
      assert is_pid(signal2.data.child_pid)
    end

    test "stops processing on first error", %{state: state} do
      task = fn -> Process.sleep(1000) end

      directives = [
        %Spawn{module: Task, args: task},
        :invalid_directive
      ]

      {:error, error} = Directive.handle(state, directives)

      # Should only receive one process_started signal
      assert_receive {:signal, signal}
      assert signal.type == Signal.process_started()
      refute_receive {:signal, _}

      assert_error_match(error, %Error{
        type: :validation_error,
        message: "Invalid directive",
        details: %{directive: :invalid_directive}
      })
    end

    test "handles single directive", %{state: state} do
      task = fn -> Process.sleep(350) end
      directive = %Spawn{module: Task, args: task}

      {:ok, new_state} = Directive.handle(state, directive)
      assert state == new_state

      assert_receive {:signal, signal}
      assert signal.type == Signal.process_started()
      assert is_pid(signal.data.child_pid)
    end
  end

  describe "process management directives" do
    test "spawn creates a new child process", %{state: state} do
      task = fn -> Process.sleep(1000) end
      directive = %Spawn{module: Task, args: task}
      {:ok, new_state} = Directive.execute(state, directive)
      assert state == new_state

      # Verify we received the process_started signal
      assert_receive {:signal, signal}
      assert signal.type == Signal.process_started()
      assert is_pid(signal.data.child_pid)

      assert signal.data.child_spec == %{
               id: signal.data.child_spec.id,
               start: {Task, :start_link, [task]},
               restart: :temporary,
               type: :worker
             }
    end

    test "kill terminates a specific process", %{state: state} do
      task = fn -> Process.sleep(1000) end
      spawn_directive = %Spawn{module: Task, args: task}
      {:ok, state} = Directive.execute(state, spawn_directive)

      # Clear the spawn signal
      assert_receive {:signal, _}

      # Get the PID from the state's child processes
      pid = DynamicSupervisor.which_children(state.child_supervisor) |> hd() |> elem(1)
      assert Process.alive?(pid)

      kill_directive = %Kill{pid: pid}
      {:ok, new_state} = Directive.execute(state, kill_directive)
      refute Process.alive?(pid)
      assert state == new_state

      # Verify we received the process_terminated signal
      assert_receive {:signal, signal}
      assert signal.type == Signal.process_terminated()
      assert signal.data.child_pid == pid
    end

    test "kill returns error for non-existent process", %{state: state} do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)

      directive = %Kill{pid: non_existent_pid}
      {:error, error} = Directive.execute(state, directive)

      assert_error_match(error, %Error{
        type: :execution_error,
        message: "Process not found",
        details: %{pid: non_existent_pid}
      })
    end
  end

  describe "error handling" do
    test "returns error for invalid directive", %{state: state} do
      {:error, error} = Directive.execute(state, :invalid_directive)

      assert_error_match(error, %Error{
        type: :validation_error,
        message: "Invalid directive",
        details: %{directive: :invalid_directive}
      })
    end
  end
end
