defmodule JidoTest.Agent.Server.RuntimeInputTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Runtime
  alias Jido.Instruction
  alias Jido.Signal
  alias Jido.Signal.Router
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestActions
  alias Jido.Agent.Server.Signal, as: ServerSignal

  @moduletag :capture_log
  @moduletag timeout: 30000

  setup do
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = BasicAgent.new("test")

    # Register test actions with the agent
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.ErrorAction)
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.DelayAction)
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.NoSchema)

    router =
      Router.new!([
        {"test_action", %Instruction{action: TestActions.NoSchema}},
        {"error_action", %Instruction{action: TestActions.ErrorAction}},
        {"delay_action", %Instruction{action: TestActions.DelayAction}}
      ])

    state = %ServerState{
      agent: agent,
      child_supervisor: supervisor,
      dispatch: [
        {:pid, [target: self(), delivery_mode: :async]}
      ],
      status: :idle,
      pending_signals: :queue.new(),
      router: router,
      max_queue_size: 10000
    }

    {:ok, state: state}
  end

  describe "handle_async_signal/2" do
    test "successfully enqueues and processes a signal", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      assert {:ok, final_state} = Runtime.handle_async_signal(state, signal)

      # Verify state is cleaned up properly
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.pending_signals)
      assert is_nil(final_state.current_signal)
      assert is_nil(final_state.current_signal_type)

      # Verify signal result is emitted
      assert_receive {:signal, result_signal}

      assert result_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))

      assert result_signal.data == %{result: 3}
      assert result_signal.jido_correlation_id == signal.jido_correlation_id
      assert is_binary(result_signal.jido_causation_id)

      # Verify final signal result
      assert_receive {:signal, final_signal}

      assert final_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:out, :signal_result}))

      assert final_signal.data == %{result: 3}
      assert final_signal.jido_correlation_id == signal.jido_correlation_id
      assert is_binary(final_signal.jido_causation_id)
    end

    test "handles queue overflow error", %{state: state} do
      state = %{state | max_queue_size: 0}
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})

      assert {:error, :queue_overflow} = Runtime.handle_async_signal(state, signal)
      assert_receive {:signal, overflow_signal}

      assert overflow_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:event, :queue_overflow}))
    end

    test "handles signal execution error", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}})
      assert {:error, _reason} = Runtime.handle_async_signal(state, signal)

      assert_receive {:signal, error_signal}

      assert error_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:err, :execution_error}))
    end

    test "handles invalid signal type", %{state: state} do
      invalid_signal = Signal.new!(%{type: "invalid_type", data: %{}})
      assert {:error, _reason} = Runtime.handle_async_signal(state, invalid_signal)

      assert_receive {:signal, error_signal}

      assert error_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:err, :execution_error}))
    end
  end

  describe "handle_sync_signal/2" do
    test "successfully executes signal and returns result", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      assert {:ok, final_state, result} = Runtime.handle_sync_signal(state, signal)

      # Verify result
      assert result == %{result: 3}

      # Verify state
      assert final_state.status == :idle
      assert final_state.current_correlation_id == signal.jido_correlation_id
    end

    test "preserves correlation ID", %{state: state} do
      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1},
          jido_correlation_id: "test-correlation"
        })

      assert {:ok, final_state, _result} = Runtime.handle_sync_signal(state, signal)
      assert final_state.current_correlation_id == "test-correlation"
    end

    test "handles execution error", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}})
      assert {:error, _reason} = Runtime.handle_sync_signal(state, signal)

      # # No error signal should be emitted for sync signals
      # refute_receive {:signal, _error_signal}
    end

    test "handles invalid signal", %{state: state} do
      invalid_signal = Signal.new!(%{type: "invalid_type", data: %{}})
      assert {:error, _reason} = Runtime.handle_sync_signal(state, invalid_signal)

      # # No error signal should be emitted for sync signals
      # refute_receive {:signal, _error_signal}
    end
  end

  describe "process_signal_queue/1" do
    test "returns {:ok, state} when queue is empty", %{state: state} do
      assert {:ok, state} = Runtime.process_signal_queue(state)
      assert state.status == :idle
    end

    test "processes single signal in step mode", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      {:ok, state_with_signal} = Jido.Agent.Server.State.enqueue(state, signal)
      state_with_signal = %{state_with_signal | mode: :step}

      assert {:ok, final_state} = Runtime.process_signal_queue(state_with_signal)
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.pending_signals)

      # Receive instruction result signal
      assert_receive {:signal, instruction_signal}

      assert instruction_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))

      assert instruction_signal.data == %{result: 3}

      # Receive final signal result
      assert_receive {:signal, output_signal}

      assert output_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:out, :signal_result}))

      assert output_signal.data == %{result: 3}
    end

    test "processes multiple signals in auto mode", %{state: state} do
      signals = [
        Signal.new!(%{type: "test_action", data: %{value: 1}}),
        Signal.new!(%{type: "test_action", data: %{value: 2}})
      ]

      state_with_signals =
        Enum.reduce(signals, state, fn signal, acc ->
          {:ok, updated_state} = Jido.Agent.Server.State.enqueue(acc, signal)
          updated_state
        end)

      state_with_signals = %{state_with_signals | mode: :auto}

      assert {:ok, final_state} = Runtime.process_signal_queue(state_with_signals)
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.pending_signals)

      # First signal execution
      assert_receive {:signal, first_instruction}

      assert first_instruction.type ==
               ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))

      assert first_instruction.data == %{result: 3}

      assert_receive {:signal, first_result}

      assert first_result.type ==
               ServerSignal.join_type(ServerSignal.type({:out, :signal_result}))

      assert first_result.data == %{result: 3}

      # Second signal execution
      assert_receive {:signal, second_instruction}

      assert second_instruction.type ==
               ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))

      assert second_instruction.data == %{result: 4}

      assert_receive {:signal, second_result}

      assert second_result.type ==
               ServerSignal.join_type(ServerSignal.type({:out, :signal_result}))

      assert second_result.data == %{result: 4}
    end
  end

  describe "execute_signal/2" do
    test "returns {:ok, state, result} when signal execution is successful", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      {:ok, final_state, result} = Runtime.execute_signal(state, signal)
      assert result == %{result: 3}
      assert final_state.status == :idle
    end

    test "handles signal callback processing", %{state: state} do
      state = %{state | current_correlation_id: "test-correlation"}

      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1},
          jido_correlation_id: "test-correlation"
        })

      {:ok, final_state, _result} = Runtime.execute_signal(state, signal)
      assert final_state.current_correlation_id == signal.jido_correlation_id
    end

    test "routes signal to correct instruction", %{state: state} do
      # Test each routed action type
      signals = [
        {"test_action", %{value: 1}, %{result: 3}},
        {"delay_action", %{delay: 0}, %{result: "Async workflow completed"}},
        # Changed to match any error
        {"error_action", %{}, :error}
      ]

      for {type, data, expected} <- signals do
        signal = Signal.new!(%{type: type, data: data})

        case expected do
          :error ->
            assert {:error, _reason} = Runtime.execute_signal(state, signal)

          expected_result ->
            {:ok, _final_state, result} = Runtime.execute_signal(state, signal)
            assert result == expected_result
        end
      end
    end

    test "applies signal data to first instruction", %{state: state} do
      # Signal data should be merged with instruction params
      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1, extra: "data"}
        })

      {:ok, _final_state, result} = Runtime.execute_signal(state, signal)
      assert result == %{result: 3}
    end

    test "handles errors during signal routing", %{state: state} do
      signal = Signal.new!(%{type: "unknown_action", data: %{}})
      assert {:error, _reason} = Runtime.execute_signal(state, signal)
    end

    test "handles errors during instruction execution", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}})
      assert {:error, _reason} = Runtime.execute_signal(state, signal)
    end

    test "maintains state through execution chain", %{state: state} do
      state = %{
        state
        | current_correlation_id: "test-correlation",
          current_causation_id: "test-causation"
      }

      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1},
          jido_correlation_id: "test-correlation",
          jido_causation_id: "test-causation"
        })

      {:ok, final_state, _result} = Runtime.execute_signal(state, signal)

      # Check state is maintained
      assert final_state.current_correlation_id == signal.jido_correlation_id
      assert final_state.current_causation_id == signal.jido_causation_id
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.pending_signals)
    end

    test "handles empty signal data", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: nil})
      {:ok, _final_state, result} = Runtime.execute_signal(state, signal)
      assert result == %{result: "No params"}
    end

    test "processes signal opts correctly", %{state: state} do
      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1},
          opts: [test_opt: true]
        })

      {:ok, _final_state, result} = Runtime.execute_signal(state, signal)
      assert result == %{result: 3}
    end

    test "handles invalid signal format", %{state: state} do
      invalid_signals = [
        nil,
        # Not a Signal struct
        %{type: "test_action"},
        # Invalid signal
        Signal.new!(%{type: "test", data: %{}}) |> Map.put(:type, nil)
      ]

      for invalid_signal <- invalid_signals do
        assert {:error, _reason} = Runtime.execute_signal(state, invalid_signal)
      end
    end
  end
end
