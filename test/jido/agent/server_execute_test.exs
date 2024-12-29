defmodule JidoTest.Agent.Server.ExecuteTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.{Execute, State}
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Signal
  alias Jido.Error
  alias Jido.Runner.Result
  alias JidoTest.TestAgents.{BasicAgent, ErrorHandlingAgent, SyscallAgent}
  alias JidoTest.TestActions
  alias Jido.Agent.Syscall.{SpawnSyscall, KillSyscall, SubscribeSyscall}

  @moduletag :capture_log

  setup do
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = BasicAgent.new("test")

    state = %State{
      agent: agent,
      child_supervisor: supervisor,
      pubsub: TestPubSub,
      topic: "test_topic",
      status: :idle,
      pending_signals: :queue.new()
    }

    :ok = Phoenix.PubSub.subscribe(TestPubSub, state.topic)
    {:ok, state: state}
  end

  describe "process_signal/2" do
    test "processes signal by enqueuing and executing", %{state: state} do
      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          TestActions.NoSchema,
          %{value: 1},
          apply_state: true
        )

      assert {:ok, new_state} = Execute.process_signal(state, signal)
      assert new_state.status == :idle

      # Verify PubSub events
      assert_receive %Signal{type: type, data: %{queue_size: _}} = _received
      assert type == ServerSignal.queue_processing_started()

      # Verify state transitions for agent signal execution
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{}} = _received
      assert type == ServerSignal.cmd_success()
    end

    test "emits queue overflow event on enqueue error", %{state: state} do
      # Force an enqueue error by setting max queue size to 0
      state = %{state | max_queue_size: 0}

      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          TestActions.NoSchema,
          %{value: 1},
          apply_state: true
        )

      assert {:error, :queue_overflow} = Execute.process_signal(state, signal)

      assert_receive %Signal{type: type, data: %{queue_size: 0, max_size: 0}} = _received
      assert type == ServerSignal.queue_overflow()
    end
  end

  describe "process_signal_queue/1" do
    test "processes signals until queue is empty", %{state: state} do
      # Create 3 test signals (reduced from 10 for clearer event tracking)
      qty = 3

      signals =
        for i <- 1..qty do
          {:ok, signal} =
            ServerSignal.action_signal(
              "test-agent",
              JidoTest.TestActions.NoSchema,
              %{command: :"cmd#{i}"},
              apply_state: true
            )

          signal
        end

      # Enqueue all signals
      state_with_signals =
        Enum.reduce(signals, state, fn signal, acc_state ->
          {:ok, new_state} = State.enqueue(acc_state, signal)
          new_state
        end)

      assert {:ok, final_state} = Execute.process_signal_queue(state_with_signals)
      assert :queue.is_empty(final_state.pending_signals)

      # Verify PubSub events for queue processing
      assert_receive %Signal{type: type, data: %{queue_size: ^qty}} = _received
      assert type == ServerSignal.queue_processing_started()

      # Should receive state transitions for each signal
      for _signal <- signals do
        assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
        assert type == ServerSignal.transition_succeeded()

        assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
        assert type == ServerSignal.transition_succeeded()
      end

      assert_receive %Signal{type: type, data: %{}} = _received
      assert type == ServerSignal.cmd_success()
    end

    test "ignores unknown signal types and continues processing", %{state: state} do
      # Create a mix of valid and invalid signals
      {:ok, valid1} =
        ServerSignal.action_signal("test-agent", JidoTest.TestActions.NoSchema, %{command: :cmd1})

      {:ok, valid2} =
        ServerSignal.action_signal("test-agent", JidoTest.TestActions.NoSchema, %{command: :cmd2})

      signals = [
        valid1,
        %Signal{
          id: "invalid_id",
          source: "/test/source",
          type: "invalid.type",
          data: %{}
        },
        valid2
      ]

      # Enqueue all signals
      state_with_signals =
        Enum.reduce(signals, state, fn signal, acc_state ->
          {:ok, new_state} = State.enqueue(acc_state, signal)
          new_state
        end)

      assert {:ok, final_state} = Execute.process_signal_queue(state_with_signals)
      assert :queue.is_empty(final_state.pending_signals)

      # Verify PubSub events
      assert_receive %Signal{type: type, data: %{queue_size: 3}} = _received
      assert type == ServerSignal.queue_processing_started()

      # First valid signal
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{completed_signal: ^valid1}} = _received
      assert type == ServerSignal.queue_step_completed()

      # Invalid signal
      assert_receive %Signal{
                       type: type,
                       data: %{
                         ignored_signal: %{type: "invalid.type"},
                         reason: {:unknown_signal_type, "invalid.type"}
                       }
                     } = _received

      assert type == ServerSignal.queue_step_ignored()

      # Second valid signal
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{completed_signal: ^valid2}} = _received
      assert type == ServerSignal.queue_step_completed()

      # Queue completed
      assert_receive %Signal{type: type, data: %{}} = _received
      assert type == ServerSignal.cmd_success()
    end

    test "processes unknown signal type with ignore event", %{state: state} do
      invalid_signal = %Signal{
        id: "invalid_id",
        source: "/test/source",
        type: "invalid.type",
        data: %{}
      }

      {:ok, state_with_signal} = State.enqueue(state, invalid_signal)

      assert {:ok, final_state} = Execute.process_signal_queue(state_with_signal)
      assert :queue.is_empty(final_state.pending_signals)

      # Verify events in sequence
      # 1. Queue processing started
      assert_receive %Signal{type: type, data: %{queue_size: 1}} = _received
      assert type == ServerSignal.queue_processing_started()

      # 2. Signal ignored and step completed
      assert_receive %Signal{
                       type: type,
                       data: %{
                         ignored_signal: ^invalid_signal,
                         reason: {:unknown_signal_type, "invalid.type"}
                       }
                     } = _received

      assert type == ServerSignal.queue_step_ignored()

      # 3. Queue processing completed
      assert_receive %Signal{type: type, data: %{}} = _received
      assert type == ServerSignal.queue_processing_completed()

      # 4. No more events
      refute_receive %Signal{}
    end
  end

  describe "execute_signal/2" do
    test "executes agent command signal with events", %{state: state} do
      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          TestActions.NoSchema,
          %{value: 1},
          apply_state: true
        )

      assert {:ok, _new_state} = Execute.execute_signal(state, signal)

      # Verify state transitions
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == ServerSignal.transition_succeeded()
    end

    @tag :skip
    test "executes process start signal with events", %{state: state} do
      signal = %Signal{
        id: Jido.Util.generate_id(),
        source: "/agent/test",
        type: ServerSignal.process_start(),
        data: %{child_spec: {Task, fn -> Process.sleep(5000) end}}
      }

      assert {:ok, _new_state} = Execute.execute_signal(state, signal)

      # Verify state transitions
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == ServerSignal.transition_succeeded()

      # Verify process started event
      assert_receive %Signal{type: type, data: %{child_spec: _, child_pid: pid}} = _received
      assert type == ServerSignal.process_started()
      assert is_pid(pid)
    end

    test "returns error for unknown signal type", %{state: state} do
      signal = %Signal{
        id: Jido.Util.generate_id(),
        source: "/agent/test",
        type: "unknown.type",
        data: %{}
      }

      assert {:ignore, {:unknown_signal_type, "unknown.type"}} =
               Execute.execute_signal(state, signal)
    end
  end

  # describe "execute_syscall_signal/2" do
  #   test "executes process start signal with events", %{state: state} do
  #     signal = %Signal{
  #       id: Jido.Util.generate_id(),
  #       source: "/agent/test",
  #       type: ServerSignal.process_start(),
  #       data: %{child_spec: {Task, fn -> Process.sleep(5000) end}}
  #     }

  #     assert {:ok, _new_state} = Execute.execute_syscall_signal(state, signal)

  #     # Verify signal execution started event
  #     assert_receive %Signal{type: type} = _received
  #     assert type == ServerSignal.signal_execution_started()

  #     # Verify process started event
  #     assert_receive %Signal{type: type, data: %{child_spec: _, child_pid: pid}} = _received
  #     assert type == ServerSignal.process_started()
  #     assert is_pid(pid)

  #     # Verify signal execution completed event
  #     assert_receive %Signal{type: type} = _received
  #     assert type == ServerSignal.signal_execution_completed()
  #   end

  #   test "executes process terminate signal with events", %{state: state} do
  #     # Start a process first
  #     start_signal = %Signal{
  #       id: Jido.Util.generate_id(),
  #       source: "/agent/test",
  #       type: ServerSignal.process_start(),
  #       data: %{child_spec: {Task, fn -> Process.sleep(5000) end}}
  #     }

  #     {:ok, state_with_process} = Execute.execute_syscall_signal(state, start_signal)

  #     # Verify start signal execution events
  #     assert_receive %Signal{type: type} = _received
  #     assert type == ServerSignal.signal_execution_started()

  #     # Get the PID from the process_started event
  #     assert_receive %Signal{type: type, data: %{child_pid: pid}} = _received
  #     assert type == ServerSignal.process_started()

  #     assert_receive %Signal{type: type} = _received
  #     assert type == ServerSignal.signal_execution_completed()

  #     # Then terminate it
  #     terminate_signal = %Signal{
  #       id: Jido.Util.generate_id(),
  #       source: "/agent/test",
  #       type: ServerSignal.process_terminate(),
  #       data: %{child_pid: pid}
  #     }

  #     assert {:ok, _new_state} =
  #              Execute.execute_syscall_signal(state_with_process, terminate_signal)

  #     # Verify terminate signal execution events
  #     assert_receive %Signal{type: type} = _received
  #     assert type == ServerSignal.signal_execution_started()

  #     assert_receive %Signal{type: type, data: %{child_pid: ^pid}} = _received
  #     assert type == ServerSignal.process_terminated()

  #     assert_receive %Signal{type: type} = _received
  #     assert type == ServerSignal.signal_execution_completed()
  #   end

  #   test "returns error for unknown server signal", %{state: state} do
  #     signal = %Signal{
  #       id: Jido.Util.generate_id(),
  #       source: "/agent/test",
  #       type: "jido.process.unknown",
  #       data: %{}
  #     }

  #     assert {:ignore, {:unknown_server_signal, "jido.process.unknown"}} =
  #              Execute.execute_syscall_signal(state, signal)

  #     # Verify signal execution failed event
  #     assert_receive %Signal{
  #                      type: type,
  #                      data: %{reason: {:unknown_server_signal, "jido.process.unknown"}}
  #                    } = _received

  #     assert type == ServerSignal.signal_execution_failed()
  #   end
  # end

  describe "execute_agent_signal/2" do
    test "queues signal when paused", %{state: state} do
      paused_state = %{state | status: :paused}

      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          TestActions.BasicAction,
          %{value: 1},
          apply_state: true
        )

      assert {:ok, new_state} = Execute.execute_agent_signal(paused_state, signal)
      assert :queue.len(new_state.pending_signals) == 1
    end

    test "executes signal in idle state with events", %{state: state} do
      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          TestActions.NoSchema,
          %{value: 1},
          apply_state: true
        )

      assert {:ok, new_state} = Execute.execute_agent_signal(state, signal)
      assert new_state.status == :idle

      # Verify state transitions
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == ServerSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == ServerSignal.transition_succeeded()
    end

    test "returns error for invalid state", %{state: state} do
      invalid_state = %{state | status: :error}

      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          TestActions.BasicAction,
          %{value: 1},
          apply_state: true
        )

      assert {:error, {:invalid_state, :error}} =
               Execute.execute_agent_signal(invalid_state, signal)
    end
  end

  describe "agent_signal_cmd/2" do
    setup do
      basic_state = %ServerState{
        status: :running,
        agent: BasicAgent.new(),
        topic: "test.topic",
        pubsub: TestPubSub,
        pending_signals: :queue.new()
      }

      syscall_state = %ServerState{
        status: :running,
        agent: SyscallAgent.new(),
        topic: "test.topic",
        pubsub: TestPubSub,
        pending_signals: :queue.new()
      }

      error_state = %ServerState{
        status: :running,
        agent: ErrorHandlingAgent.new(),
        topic: "test.topic",
        pubsub: TestPubSub,
        pending_signals: :queue.new()
      }

      {:ok, state: basic_state, syscall_state: syscall_state, error_state: error_state}
    end

    test "executes normal action signal", %{state: state} do
      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          {TestActions.BasicAction, %{value: 1}},
          %{},
          apply_state: true
        )

      assert {:ok, agent} = Execute.agent_signal_cmd(state, signal)
      assert agent.state.value == 1
    end

    test "executes directive signal", %{state: state} do
      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          {TestActions.RegisterAction, %{action_module: TestActions.BasicAction}},
          %{},
          apply_state: true
        )

      assert {:ok, agent} = Execute.agent_signal_cmd(state, signal)
      assert agent.actions |> Enum.member?(TestActions.BasicAction)
    end

    test "executes syscall signal", %{syscall_state: state} do
      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          {Jido.Actions.Syscall.Broadcast, %{topic: "test_topic", message: "hello"}},
          %{},
          apply_state: true
        )

      assert {:ok, agent} = Execute.agent_signal_cmd(state, signal)

      [syscall] = agent.result.syscalls

      assert %Jido.Agent.Syscall.BroadcastSyscall{
               topic: "test_topic",
               message: "hello"
             } = syscall
    end

    test "returns error for invalid state", %{state: state} do
      invalid_state = %{state | status: :idle}

      {:ok, signal} =
        ServerSignal.action_signal(
          "test",
          TestActions.BasicAction,
          %{value: 1},
          apply_state: true
        )

      assert {:error, {:invalid_state, :idle}} = Execute.agent_signal_cmd(invalid_state, signal)
    end
  end

  describe "handle_action_result/2" do
    setup context do
      test_name = context.test
      supervisor_name = Module.concat(__MODULE__, "#{test_name}.Supervisor")
      {:ok, supervisor} = start_supervised({DynamicSupervisor, name: supervisor_name})

      state = %ServerState{
        status: :running,
        agent: BasicAgent.new(),
        topic: "test.topic",
        pubsub: TestPubSub,
        pending_signals: :queue.new(),
        child_supervisor: supervisor,
        subscriptions: []
      }

      {:ok, state: state}
    end

    test "handles syscalls successfully", %{state: state} do
      syscalls = [
        %SpawnSyscall{module: Task, args: fn -> :ok end},
        %SubscribeSyscall{topic: "test.topic"}
      ]

      updated_agent = %{
        state.agent
        | result: %Result{
            status: :ok,
            syscalls: syscalls
          }
      }

      assert {:ok, updated_state} = Execute.handle_agent_result(state, updated_agent)
      assert updated_state.status == :running
      assert updated_state.subscriptions == ["test.topic"]
    end

    test "handles syscall errors", %{state: state} do
      syscalls = [
        %{__struct__: :invalid_syscall}
      ]

      updated_agent = %{
        state.agent
        | result: %Result{
            status: :ok,
            syscalls: syscalls
          }
      }

      assert {:error,
              %Error{
                type: :validation_error,
                message: "Invalid syscall",
                details: %{syscall: %{__struct__: :invalid_syscall}}
              }} = Execute.handle_agent_result(state, updated_agent)
    end

    test "handles empty syscalls list", %{state: state} do
      updated_agent = %{
        state.agent
        | result: %Result{
            status: :ok,
            syscalls: []
          }
      }

      assert {:ok, updated_state} = Execute.handle_agent_result(state, updated_agent)
      assert updated_state.agent.id == state.agent.id
      assert updated_state.agent.result.status == :ok
    end

    test "handles error in result", %{state: state} do
      updated_agent = %{
        state.agent
        | result: %Result{
            status: :error,
            error: %Error{type: :test_error, message: "test error"}
          }
      }

      assert {:error, error} = Execute.handle_agent_result(state, updated_agent)
      assert error.type == :test_error
      assert error.message == "test error"
    end

    test "handles state update result", %{state: state} do
      updated_agent = %{
        state.agent
        | result: %Result{
            status: :ok,
            result_state: %{battery_level: 50, location: :work}
          }
      }

      assert {:ok, updated_state} = Execute.handle_agent_result(state, updated_agent)
      assert updated_state.agent.result.result_state.battery_level == 50
      assert updated_state.agent.result.result_state.location == :work
      assert updated_state.status == :running
    end
  end

  describe "handle_syscalls/2" do
    setup context do
      test_name = context.test
      supervisor_name = Module.concat(__MODULE__, "#{test_name}.Supervisor")
      {:ok, supervisor} = start_supervised({DynamicSupervisor, name: supervisor_name})

      state = %ServerState{
        status: :running,
        agent: BasicAgent.new(),
        topic: "test.topic",
        pubsub: TestPubSub,
        pending_signals: :queue.new(),
        child_supervisor: supervisor,
        subscriptions: []
      }

      {:ok, state: state}
    end

    test "executes valid syscalls successfully", %{state: state} do
      syscalls = [
        %SpawnSyscall{module: Task, args: fn -> :ok end},
        %SpawnSyscall{module: Task, args: fn -> :ok end}
      ]

      assert {:ok, final_state} = Execute.handle_syscalls(state, syscalls)
      assert final_state.status == :running
    end

    test "accumulates subscriptions from multiple subscribe syscalls", %{state: state} do
      syscalls = [
        %SubscribeSyscall{topic: "topic1"},
        %SubscribeSyscall{topic: "topic2"}
      ]

      assert {:ok, final_state} = Execute.handle_syscalls(state, syscalls)
      assert "topic1" in final_state.subscriptions
      assert "topic2" in final_state.subscriptions
      assert length(final_state.subscriptions) == 2
    end

    test "halts on invalid syscall", %{state: state} do
      syscalls = [
        %SpawnSyscall{module: Task, args: fn -> :ok end},
        :invalid_syscall,
        %SpawnSyscall{module: Task, args: fn -> :ok end}
      ]

      assert {:error,
              %Error{
                type: :validation_error,
                message: "Invalid syscall",
                details: %{syscall: :invalid_syscall}
              }} = Execute.handle_syscalls(state, syscalls)
    end

    test "halts on syscall error", %{state: state} do
      pid = spawn(fn -> :ok end)
      Process.exit(pid, :kill)

      syscalls = [
        %SpawnSyscall{module: Task, args: fn -> :ok end},
        %KillSyscall{pid: pid}
      ]

      assert {:error,
              %Error{
                type: :execution_error,
                message: "Process not found",
                details: %{pid: ^pid}
              }} = Execute.handle_syscalls(state, syscalls)
    end

    test "handles empty syscalls list", %{state: state} do
      assert {:ok, ^state} = Execute.handle_syscalls(state, [])
    end
  end

  describe "ensure_running_state/1" do
    setup do
      state = %ServerState{
        status: :idle,
        agent: BasicAgent.new(),
        topic: "test.topic",
        pubsub: TestPubSub,
        pending_signals: :queue.new()
      }

      {:ok, state: state}
    end

    test "transitions from idle to running", %{state: state} do
      assert {:ok, running_state} = Execute.ensure_running_state(state)
      assert running_state.status == :running
    end

    test "maintains running state", %{state: state} do
      running_state = %{state | status: :running}
      assert {:ok, ^running_state} = Execute.ensure_running_state(running_state)
    end

    test "returns error for invalid states", %{state: state} do
      invalid_states = [:error, :paused, :terminated]

      for status <- invalid_states do
        invalid_state = %{state | status: status}
        assert {:error, {:invalid_state, ^status}} = Execute.ensure_running_state(invalid_state)
      end
    end
  end
end
