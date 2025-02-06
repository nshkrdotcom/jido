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

  describe "execute_agent_instructions/2" do
    test "successfully executes instructions", %{state: state} do
      instructions = [%Instruction{action: TestActions.NoSchema, params: %{value: 1}}]
      assert {:ok, final_state, result} = Runtime.execute_agent_instructions(state, instructions)
      assert result == %{result: 3}
      assert final_state.agent.result == %{result: 3}
    end

    test "sets causation_id from first instruction", %{state: state} do
      instructions = [
        %Instruction{id: "test-id", action: TestActions.NoSchema, params: %{value: 1}}
      ]

      assert {:ok, final_state, _result} = Runtime.execute_agent_instructions(state, instructions)
      assert final_state.current_causation_id == "test-id"
    end

    test "handles error from agent execution", %{state: state} do
      instructions = [%Instruction{action: TestActions.ErrorAction}]
      assert {:error, _reason} = Runtime.execute_agent_instructions(state, instructions)
    end

    test "handles invalid instruction format", %{state: state} do
      instructions = [:invalid]
      assert {:error, _reason} = Runtime.execute_agent_instructions(state, instructions)
    end

    test "preserves correlation_id through execution", %{state: state} do
      state = %{state | current_correlation_id: "test-correlation"}
      instructions = [%Instruction{action: TestActions.NoSchema, params: %{value: 1}}]
      assert {:ok, final_state, _result} = Runtime.execute_agent_instructions(state, instructions)
      assert final_state.current_correlation_id == "test-correlation"
    end
  end

  describe "execute_signal/2" do
    test "returns {:ok, state, result} when signal execution is successful", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      assert {:ok, final_state, result} = Runtime.handle_sync_signal(state, signal)
      assert final_state.status == :idle
      # NoSchema action returns %{result: value + 2}
      assert result == %{result: 3}
    end

    test "preserves correlation ID through execution", %{state: state} do
      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1},
          jido_correlation_id: "test-correlation"
        })

      assert {:ok, final_state, _result} = Runtime.handle_sync_signal(state, signal)
      assert final_state.current_correlation_id == "test-correlation"
    end

    test "returns error when signal execution fails", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}})
      assert {:error, _reason} = Runtime.handle_sync_signal(state, signal)
    end

    test "handles invalid signal type", %{state: state} do
      signal = Signal.new!(%{type: "unknown_action", data: %{}})
      assert {:error, _reason} = Runtime.handle_sync_signal(state, signal)
    end
  end

  describe "enqueue_and_execute/2" do
    test "successfully enqueues and executes a signal", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      assert {:ok, final_state} = Runtime.handle_async_signal(state, signal)
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

    test "handles enqueue error", %{state: state} do
      # Set queue size to 0 to force enqueue error
      state = %{state | max_queue_size: 0}
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})

      assert {:error, :queue_overflow} = Runtime.handle_async_signal(state, signal)
      # Should receive queue overflow log signal
      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:event, :queue_overflow}))
    end

    test "handles execution error", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}})
      assert {:error, _reason} = Runtime.handle_async_signal(state, signal)

      # Receive error signal
      assert_receive {:signal, error_signal}

      assert error_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:err, :execution_error}))
    end

    test "handles invalid signal", %{state: state} do
      # Create a Signal with invalid type
      invalid_signal =
        Signal.new!(%{
          type: "invalid_type",
          data: %{},
          source: "test",
          id: "test-id"
        })

      assert {:error, _reason} = Runtime.handle_async_signal(state, invalid_signal)

      # Should receive error signal
      assert_receive {:signal, error_signal}

      assert error_signal.type ==
               ServerSignal.join_type(ServerSignal.type({:err, :execution_error}))
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

  describe "route_signal/2" do
    setup %{state: state} do
      router =
        Router.new!([
          {"test_action", %Instruction{action: TestActions.NoSchema}},
          {"delay_action", %Instruction{action: TestActions.DelayAction}}
        ])

      state = %{state | router: router}
      {:ok, state: state}
    end

    test "returns {:ok, instructions} when signal matches a route", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{foo: "bar"}})

      assert {:ok, [%Instruction{action: TestActions.NoSchema} | _]} =
               Runtime.route_signal(state, signal)
    end

    test "returns {:ok, instructions} when signal matches delay route", %{state: state} do
      signal = Signal.new!(%{type: "delay_action", data: %{foo: "bar"}})

      assert {:ok, [%Instruction{action: TestActions.DelayAction} | _]} =
               Runtime.route_signal(state, signal)
    end

    test "returns error when signal type doesn't match any routes", %{state: state} do
      signal = Signal.new!(%{type: "unknown_action", data: %{foo: "bar"}})
      assert {:error, _reason} = Runtime.route_signal(state, signal)
    end

    test "returns error when signal is invalid", %{state: state} do
      assert {:error, _reason} = Runtime.route_signal(state, :invalid_signal)
    end

    test "returns error when router is not configured", %{state: base_state} do
      state = %{base_state | router: nil}
      signal = Signal.new!(%{type: "test_action", data: %{foo: "bar"}})
      assert {:error, _reason} = Runtime.route_signal(state, signal)
    end
  end
end
