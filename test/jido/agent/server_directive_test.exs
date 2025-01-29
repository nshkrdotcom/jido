defmodule Jido.Agent.Server.DirectiveTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Server.{Directive, State, Signal}
  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Error

  alias Jido.Agent.Directive.{
    Spawn,
    Kill,
    Enqueue,
    RegisterAction,
    DeregisterAction
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
      dispatch: {:pid, [target: self(), delivery_mode: :async]},
      status: :idle,
      pending_signals: :queue.new()
    }

    {:ok, state: state}
  end

  describe "instruction queue directives" do
    test "enqueue adds instruction to queue", %{state: state} do
      directive = %Enqueue{
        action: :test_action,
        params: %{value: 42},
        context: %{user: "test"},
        opts: [priority: :high]
      }

      {:ok, new_state} = Directive.execute(state, directive)

      # Verify instruction was added to queue
      assert :queue.len(new_state.pending_signals) == 1
      {{:value, instruction}, _} = :queue.out(new_state.pending_signals)
      assert instruction.action == :test_action
      assert instruction.params == %{value: 42}
      assert instruction.context == %{user: "test"}
      assert instruction.opts == [priority: :high]
    end

    test "enqueue fails with invalid action", %{state: state} do
      directive = %Enqueue{action: nil}
      {:error, error} = Directive.execute(state, directive)

      assert_error_match(error, %Error{
        type: :validation_error,
        message: "Invalid action",
        details: %{action: nil}
      })
    end
  end

  describe "action registration directives" do
    defmodule TestAction do
      def run(_params, _context), do: {:ok, nil}
    end

    test "register adds action module", %{state: state} do
      directive = %RegisterAction{action_module: TestAction}
      {:ok, new_state} = Directive.execute(state, directive)

      # Verify action was registered
      assert TestAction in new_state.agent.actions
    end

    test "register fails with invalid module", %{state: state} do
      directive = %RegisterAction{action_module: :not_a_module}
      {:error, error} = Directive.execute(state, directive)

      assert_error_match(error, %Error{
        type: :validation_error,
        message: "Invalid action module",
        details: %{module: :not_a_module}
      })
    end

    test "deregister removes action module", %{state: state} do
      # First register the action
      {:ok, state_with_action} =
        Directive.execute(state, %RegisterAction{action_module: TestAction})

      # Then deregister it
      directive = %DeregisterAction{action_module: TestAction}
      {:ok, final_state} = Directive.execute(state_with_action, directive)

      # Verify action was removed
      refute TestAction in final_state.agent.actions
    end

    test "deregister fails with invalid module", %{state: state} do
      directive = %DeregisterAction{action_module: :not_a_module}
      {:error, error} = Directive.execute(state, directive)

      assert_error_match(error, %Error{
        type: :validation_error,
        message: "Invalid action module",
        details: %{module: :not_a_module}
      })
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
