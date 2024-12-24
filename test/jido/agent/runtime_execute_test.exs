defmodule JidoTest.Agent.Runtime.ExecuteTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Runtime.{Execute, State}
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  alias Jido.Signal
  alias JidoTest.TestAgents.SimpleAgent

  @moduletag :capture_log

  setup do
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = SimpleAgent.new("test")

    state = %State{
      agent: agent,
      child_supervisor: supervisor,
      pubsub: TestPubSub,
      topic: "test_topic",
      status: :idle,
      pending: :queue.new()
    }

    :ok = Phoenix.PubSub.subscribe(TestPubSub, state.topic)
    {:ok, state: state}
  end

  describe "process_signal/2" do
    test "processes signal by enqueuing and executing", %{state: state} do
      signal = %Signal{
        id: "test_id",
        source: "/test/source",
        type: "jido.agent.cmd",
        data: %{command: :test_cmd},
        extensions: %{
          "actions" => [JidoTest.TestActions.NoSchema],
          "apply_state" => true
        }
      }

      assert {:ok, new_state} = Execute.process_signal(state, signal)
      assert new_state.status == :idle

      # Verify PubSub events
      assert_receive %Signal{type: type, data: %{queue_size: _}} = _received
      assert type == RuntimeSignal.queue_processing_started()

      # Verify state transitions for agent signal execution
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == RuntimeSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == RuntimeSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{}} = _received
      assert type == RuntimeSignal.queue_step_completed()
    end

    test "emits queue overflow event on enqueue error", %{state: state} do
      # Force an enqueue error by setting max queue size to 0
      state = %{state | max_queue_size: 0}

      signal = %Signal{
        id: "test_id",
        source: "/test/source",
        type: "jido.agent.cmd",
        data: %{},
        extensions: %{
          "actions" => [JidoTest.TestActions.NoSchema],
          "apply_state" => true
        }
      }

      assert {:error, :queue_overflow} = Execute.process_signal(state, signal)

      assert_receive %Signal{type: type, data: %{queue_size: 0, max_size: 0}} = _received
      assert type == RuntimeSignal.queue_overflow()
    end
  end

  describe "process_signal_queue/1" do
    test "processes signals until queue is empty", %{state: state} do
      # Create 3 test signals (reduced from 10 for clearer event tracking)
      signals =
        for i <- 1..3 do
          %Signal{
            id: "signal#{i}_id",
            source: "/test/source",
            type: "jido.agent.cmd",
            data: %{command: :"cmd#{i}"},
            extensions: %{
              "actions" => [JidoTest.TestActions.NoSchema],
              "apply_state" => true
            }
          }
        end

      # Enqueue all signals
      state_with_signals =
        Enum.reduce(signals, state, fn signal, acc_state ->
          {:ok, new_state} = State.enqueue(acc_state, signal)
          new_state
        end)

      assert {:ok, final_state} = Execute.process_signal_queue(state_with_signals)
      assert :queue.is_empty(final_state.pending)

      # Verify PubSub events for queue processing
      assert_receive %Signal{type: type, data: %{queue_size: 3}} = _received
      assert type == RuntimeSignal.queue_processing_started()

      # Should receive state transitions for each signal
      for _signal <- signals do
        assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
        assert type == RuntimeSignal.transition_succeeded()

        assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
        assert type == RuntimeSignal.transition_succeeded()
      end

      assert_receive %Signal{type: type, data: %{}} = _received
      assert type == RuntimeSignal.queue_step_completed()
    end

    test "ignores unknown signal types and continues processing", %{state: state} do
      # Create a mix of valid and invalid signals
      signals = [
        %Signal{
          id: "valid1_id",
          source: "/test/source",
          type: "jido.agent.cmd",
          data: %{command: :cmd1},
          extensions: %{
            "actions" => [JidoTest.TestActions.NoSchema],
            "apply_state" => true
          }
        },
        %Signal{
          id: "invalid_id",
          source: "/test/source",
          type: "invalid.type",
          data: %{}
        },
        %Signal{
          id: "valid2_id",
          source: "/test/source",
          type: "jido.agent.cmd",
          data: %{command: :cmd2},
          extensions: %{
            "actions" => [JidoTest.TestActions.NoSchema],
            "apply_state" => true
          }
        }
      ]

      # Enqueue all signals
      state_with_signals =
        Enum.reduce(signals, state, fn signal, acc_state ->
          {:ok, new_state} = State.enqueue(acc_state, signal)
          new_state
        end)

      assert {:ok, final_state} = Execute.process_signal_queue(state_with_signals)
      assert :queue.is_empty(final_state.pending)

      # Verify PubSub events
      assert_receive %Signal{type: type, data: %{queue_size: 3}} = _received
      assert type == RuntimeSignal.queue_processing_started()

      # First valid signal
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == RuntimeSignal.transition_succeeded()
      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == RuntimeSignal.transition_succeeded()
      assert_receive %Signal{type: type, data: %{signal: %{id: "valid1_id"}}} = _received
      assert type == RuntimeSignal.queue_step_completed()

      # Invalid signal
      assert_receive %Signal{
                       type: type,
                       data: %{ignored: true, reason: {:unknown_signal_type, "invalid.type"}}
                     } = _received

      assert type == RuntimeSignal.queue_step_ignored()

      # Second valid signal
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == RuntimeSignal.transition_succeeded()
      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == RuntimeSignal.transition_succeeded()
      assert_receive %Signal{type: type, data: %{signal: %{id: "valid2_id"}}} = _received
      assert type == RuntimeSignal.queue_step_completed()

      # Queue completed
      assert_receive %Signal{type: type, data: %{}} = _received
      assert type == RuntimeSignal.queue_processing_completed()

      # No more events
      refute_receive %Signal{}
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
      assert :queue.is_empty(final_state.pending)

      # Verify events in sequence
      # 1. Queue processing started
      assert_receive %Signal{type: type, data: %{queue_size: 1}} = _received
      assert type == RuntimeSignal.queue_processing_started()

      # 2. Signal ignored and step completed
      assert_receive %Signal{
                       type: type,
                       data: %{
                         ignored: true,
                         reason: {:unknown_signal_type, "invalid.type"}
                       }
                     } = _received

      assert type == RuntimeSignal.queue_step_ignored()

      # 3. Queue processing completed
      assert_receive %Signal{type: type, data: %{}} = _received
      assert type == RuntimeSignal.queue_processing_completed()

      # 4. No more events
      refute_receive %Signal{}
    end
  end

  describe "execute_signal/2" do
    test "executes agent command signal with events", %{state: state} do
      signal = %Signal{
        id: Jido.Util.generate_id(),
        source: "/agent/test",
        type: RuntimeSignal.agent_cmd(),
        data: %{},
        extensions: %{
          "actions" => [JidoTest.TestActions.NoSchema],
          "apply_state" => true
        }
      }

      assert {:ok, _new_state} = Execute.execute_signal(state, signal)

      # Verify state transitions
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == RuntimeSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == RuntimeSignal.transition_succeeded()
    end

    test "executes process start signal with events", %{state: state} do
      signal = %Signal{
        id: Jido.Util.generate_id(),
        source: "/agent/test",
        type: RuntimeSignal.process_start(),
        data: %{child_spec: {Task, fn -> :ok end}}
      }

      assert {:ok, _new_state} = Execute.execute_signal(state, signal)

      assert_receive %Signal{type: type, data: %{child_spec: _, child_pid: pid}} = _received
      assert type == RuntimeSignal.process_started()
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

  describe "execute_syscall_signal/2" do
    test "executes process start signal with events", %{state: state} do
      signal = %Signal{
        id: Jido.Util.generate_id(),
        source: "/agent/test",
        type: RuntimeSignal.process_start(),
        data: %{child_spec: {Task, fn -> Process.sleep(5000) end}}
      }

      assert {:ok, _new_state} = Execute.execute_syscall_signal(state, signal)

      assert_receive %Signal{type: type, data: %{child_spec: _, child_pid: pid}} = _received
      assert type == RuntimeSignal.process_started()
      assert is_pid(pid)
    end

    test "executes process terminate signal with events", %{state: state} do
      # Start a process first
      start_signal = %Signal{
        id: Jido.Util.generate_id(),
        source: "/agent/test",
        type: RuntimeSignal.process_start(),
        data: %{child_spec: {Task, fn -> Process.sleep(5000) end}}
      }

      {:ok, state_with_process} = Execute.execute_syscall_signal(state, start_signal)

      # Get the PID from the process_started event
      assert_receive %Signal{type: type, data: %{child_pid: pid}} = _received
      assert type == RuntimeSignal.process_started()

      # Then terminate it
      terminate_signal = %Signal{
        id: Jido.Util.generate_id(),
        source: "/agent/test",
        type: RuntimeSignal.process_terminate(),
        data: %{child_pid: pid}
      }

      assert {:ok, _new_state} =
               Execute.execute_syscall_signal(state_with_process, terminate_signal)

      assert_receive %Signal{type: type, data: %{child_pid: ^pid}} = _received
      assert type == RuntimeSignal.process_terminated()
    end

    test "returns error for unknown runtime signal", %{state: state} do
      signal = %Signal{
        id: Jido.Util.generate_id(),
        source: "/agent/test",
        type: "jido.process.unknown",
        data: %{}
      }

      assert {:ignore, {:unknown_runtime_signal, "jido.process.unknown"}} =
               Execute.execute_syscall_signal(state, signal)
    end
  end

  describe "execute_agent_signal/2" do
    test "queues signal when paused", %{state: state} do
      paused_state = %{state | status: :paused}

      signal =
        RuntimeSignal.action_to_signal(
          "test",
          {JidoTest.TestActions.BasicAction, %{value: 1}},
          %{},
          apply_state: true
        )

      assert {:ok, new_state} = Execute.execute_agent_signal(paused_state, signal)
      assert :queue.len(new_state.pending) == 1
    end

    test "executes signal in idle state with events", %{state: state} do
      signal =
        RuntimeSignal.action_to_signal(
          "test",
          {JidoTest.TestActions.BasicAction, %{value: 1}},
          %{},
          apply_state: true
        )

      assert {:ok, new_state} = Execute.execute_agent_signal(state, signal)
      assert new_state.status == :idle

      # Verify state transitions
      assert_receive %Signal{type: type, data: %{from: :idle, to: :running}} = _received
      assert type == RuntimeSignal.transition_succeeded()

      assert_receive %Signal{type: type, data: %{from: :running, to: :idle}} = _received
      assert type == RuntimeSignal.transition_succeeded()
    end

    test "returns error for invalid state", %{state: state} do
      invalid_state = %{state | status: :error}

      signal =
        RuntimeSignal.action_to_signal(
          "test",
          {JidoTest.TestActions.BasicAction, %{value: 1}},
          %{},
          apply_state: true
        )

      assert {:error, {:invalid_state, :error}} =
               Execute.execute_agent_signal(invalid_state, signal)
    end
  end
end
