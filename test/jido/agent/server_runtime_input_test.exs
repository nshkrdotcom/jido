defmodule JidoTest.Agent.Server.RuntimeInputTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Runtime
  alias Jido.Instruction
  alias Jido.Signal
  alias Jido.Signal.Router
  alias Jido.Error
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestActions

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
      output: [
        out: {:pid, [target: self(), delivery_mode: :async]},
        log: {:pid, [target: self(), delivery_mode: :async]},
        err: {:pid, [target: self(), delivery_mode: :async]}
      ],
      status: :idle,
      pending_signals: :queue.new(),
      router: router,
      max_queue_size: 10000
    }

    {:ok, state: state}
  end

  describe "execute/2" do
    test "returns {:ok, state, result} when signal execution is successful", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      assert {:ok, final_state, result} = Runtime.execute(state, signal)
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

      assert {:ok, final_state, _result} = Runtime.execute(state, signal)
      assert final_state.current_correlation_id == "test-correlation"
    end

    test "returns error when signal execution fails", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}})
      assert {:error, _reason} = Runtime.execute(state, signal)
    end

    test "handles invalid signal type", %{state: state} do
      signal = Signal.new!(%{type: "unknown_action", data: %{}})
      assert {:error, _reason} = Runtime.execute(state, signal)
    end
  end

  describe "enqueue_and_execute/2" do
    test "successfully enqueues and executes a signal", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      assert {:ok, final_state} = Runtime.enqueue_and_execute(state, signal)
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.pending_signals)

      # First receive transition signal
      assert_receive {:signal, transition_signal}
      assert transition_signal.type == "jido.agent.log.jido.agent.event.transition.succeeded"

      # Then receive result signal
      assert_receive {:signal, output_signal}
      assert output_signal.type == "jido.agent.out"
      assert output_signal.data == {:ok, %{result: 3}}
    end

    test "handles enqueue error", %{state: state} do
      # Set queue size to 0 to force enqueue error
      state = %{state | max_queue_size: 0}
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})

      assert {:error, :queue_overflow} = Runtime.enqueue_and_execute(state, signal)
      # Should receive queue overflow log signal
      assert_receive {:signal, signal}
      assert signal.type == "jido.agent.log.jido.agent.event.queue.overflow"
    end

    test "handles execution error", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}})
      assert {:error, _reason} = Runtime.enqueue_and_execute(state, signal)

      # First receive transition signal
      assert_receive {:signal, transition_signal}
      assert transition_signal.type == "jido.agent.log.jido.agent.event.transition.succeeded"

      # Then receive error signal
      assert_receive {:signal, error_signal}
      assert error_signal.type == "jido.agent.error"
    end

    #   test "preserves correlation ID", %{state: state} do
    #     correlation_id = "test-correlation-id"
    #     state = %{state | current_correlation_id: correlation_id}

    #     signal =
    #       Signal.new!(%{
    #         type: "test_action",
    #         data: %{value: 1},
    #         jido_correlation_id: correlation_id
    #       })

    #     assert {:ok, final_state} = Runtime.enqueue_and_execute(state, signal)
    #     assert final_state.current_correlation_id == correlation_id

    #     # First receive transition signal
    #     assert_receive {:signal, transition_signal}
    #     assert transition_signal.type == "jido.agent.log.jido.agent.event.transition.succeeded"
    #     assert transition_signal.jido_correlation_id == correlation_id

    #     # Then receive result signal
    #     assert_receive {:signal, output_signal}
    #     assert output_signal.type == "jido.agent.out"
    #     assert output_signal.data == {:ok, %{result: 3}}
    #     assert output_signal.jido_correlation_id == correlation_id
    #   end

    test "handles invalid signal", %{state: state} do
      # Create a Signal with invalid type
      invalid_signal =
        Signal.new!(%{
          type: "invalid_type",
          data: %{},
          source: "test",
          id: "test-id"
        })

      assert {:error, _reason} = Runtime.enqueue_and_execute(state, invalid_signal)

      # Should receive error signal
      assert_receive {:signal, error_signal}
      assert error_signal.type == "jido.agent.error"
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

      # First receive transition signal
      assert_receive {:signal, transition_signal}
      assert transition_signal.type == "jido.agent.log.jido.agent.event.transition.succeeded"

      # Then receive result signal
      assert_receive {:signal, output_signal}
      assert output_signal.type == "jido.agent.out"
      assert output_signal.data == {:ok, %{result: 3}}
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

      # First signal execution (value: 1 + 2 = 3)
      assert_receive {:signal, first_transition}
      assert first_transition.type == "jido.agent.log.jido.agent.event.transition.succeeded"
      assert_receive {:signal, first_result}
      assert first_result.type == "jido.agent.out"
      assert first_result.data == {:ok, %{result: 3}}

      # Second signal execution (value: 1 + 2 = 3)
      assert_receive {:signal, second_transition}
      assert second_transition.type == "jido.agent.log.jido.agent.event.transition.succeeded"
      assert_receive {:signal, second_result}
      assert second_result.type == "jido.agent.out"
      assert second_result.data == {:ok, %{result: 3}}
    end

    # test "stops processing on error in auto mode", %{state: state} do
    #   signals = [
    #     Signal.new!(%{type: "test_action", data: %{value: 1}}),
    #     Signal.new!(%{type: "error_action", data: %{}}),
    #     Signal.new!(%{type: "test_action", data: %{value: 3}})
    #   ]

    #   state_with_signals =
    #     Enum.reduce(signals, state, fn signal, acc ->
    #       {:ok, updated_state} = Jido.Agent.Server.State.enqueue(acc, signal)
    #       updated_state
    #     end)

    #   state_with_signals = %{state_with_signals | mode: :auto}

    #   assert {:error, _reason} = Runtime.process_signal_queue(state_with_signals)

    #   # First signal execution
    #   assert_receive {:signal, first_transition}
    #   assert first_transition.type == "jido.agent.log.jido.agent.event.transition.succeeded"
    #   assert_receive {:signal, first_result}
    #   assert first_result.type == "jido.agent.out"
    #   assert first_result.data == {:ok, %{result: 3}}

    #   # Error signal
    #   assert_receive {:signal, error_signal}
    #   assert error_signal.type == "jido.agent.error"
    # end

    # test "preserves correlation ID through signal processing", %{state: state} do
    #   correlation_id = "test-correlation-id"
    #   state = %{state | current_correlation_id: correlation_id}

    #   signal =
    #     Signal.new!(%{
    #       type: "test_action",
    #       data: %{value: 1},
    #       jido_correlation_id: correlation_id
    #     })

    #   {:ok, state_with_signal} = Jido.Agent.Server.State.enqueue(state, signal)
    #   state_with_signal = %{state_with_signal | mode: :step}

    #   assert {:ok, final_state} = Runtime.process_signal_queue(state_with_signal)
    #   assert final_state.current_correlation_id == correlation_id

    #   # First receive transition signal
    #   assert_receive {:signal, transition_signal}
    #   assert transition_signal.type == "jido.agent.log.jido.agent.event.transition.succeeded"
    #   assert transition_signal.jido_correlation_id == correlation_id

    #   # Then receive result signal
    #   assert_receive {:signal, output_signal}
    #   assert output_signal.type == "jido.agent.out"
    #   assert output_signal.jido_correlation_id == correlation_id
    # end
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

  describe "plan_agent_instructions/2" do
    test "returns {:ok, state} if the agent plan is successful", %{state: state} do
      instructions = [%Instruction{action: TestActions.NoSchema}]
      assert {:ok, state} = Runtime.plan_agent_instructions(state, instructions)
      assert state.agent.pending_instructions != :queue.new()
    end

    test "returns error if agent plan fails", %{state: state} do
      instructions = [%Instruction{action: UnregisteredAction, params: %{}}]

      assert {:error, %Error{type: :config_error}} =
               Runtime.plan_agent_instructions(state, instructions)
    end

    test "emits error event on plan failure", %{state: state} do
      # Configure state with PID output for testing
      test_pid = self()

      state = %{
        state
        | output: [
            err: {:pid, [target: test_pid, delivery_mode: :async]}
          ]
      }

      # Try to plan an unregistered action
      instructions = [%Instruction{action: UnregisteredAction, params: %{}}]

      # Verify both the return value and error emission
      assert {:error, %Error{type: :config_error} = error} =
               Runtime.plan_agent_instructions(state, instructions)

      assert error.message =~ "not registered with agent"

      # Verify error was emitted through output channel
      assert_receive {:signal,
                      %Signal{
                        type: "jido.agent.error",
                        data: %{
                          message: "jido.agent.event.plan.failed",
                          metadata: %{
                            error: %Error{
                              type: :config_error,
                              message: message
                            }
                          }
                        }
                      }},
                     1000

      assert message =~ "not registered with agent"
    end

    test "handles unexpected errors from agent", %{state: state} do
      # Create an invalid instruction that will cause the agent to raise
      instructions = [:invalid]
      assert {:error, _} = Runtime.plan_agent_instructions(state, instructions)
    end

    test "preserves original state when planning fails", %{state: state} do
      # First plan a valid instruction
      valid_instructions = [%Instruction{action: TestActions.NoSchema, params: %{value: 1}}]
      {:ok, state_with_instructions} = Runtime.plan_agent_instructions(state, valid_instructions)

      # Then try to plan an invalid one
      invalid_instructions = [%Instruction{action: UnregisteredAction}]
      {:error, _} = Runtime.plan_agent_instructions(state_with_instructions, invalid_instructions)

      # Verify the original instruction is still in the queue
      [instruction] = :queue.to_list(state_with_instructions.agent.pending_instructions)
      assert instruction.action == TestActions.NoSchema
      assert instruction.params == %{value: 1}
    end

    test "successfully plans multiple instructions", %{state: state} do
      instructions = [
        %Instruction{action: TestActions.NoSchema, params: %{first: true}},
        %Instruction{action: TestActions.DelayAction, params: %{second: true}}
      ]

      assert {:ok, state} = Runtime.plan_agent_instructions(state, instructions)

      planned_instructions = :queue.to_list(state.agent.pending_instructions)
      assert length(planned_instructions) == 2

      [first, second] = planned_instructions
      assert first.action == TestActions.NoSchema
      assert first.params == %{first: true}
      assert second.action == TestActions.DelayAction
      assert second.params == %{second: true}
    end
  end

  describe "execute_signal/2" do
    test "successfully executes signal with valid instruction", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}})
      assert {:ok, final_state, result} = Runtime.execute(state, signal)
      assert final_state.status == :idle
      # NoSchema action returns %{result: value + 2}
      assert result == %{result: 3}
    end

    test "handles error action gracefully", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}})
      assert {:error, _reason} = Runtime.execute(state, signal)
    end

    test "handles delay action execution", %{state: state} do
      signal = Signal.new!(%{type: "delay_action", data: %{delay: 100}})
      assert {:ok, final_state, _result} = Runtime.execute(state, signal)
      assert final_state.status == :idle
    end

    test "fails with unregistered action", %{state: state} do
      router =
        Router.new!([
          {"invalid_action", %Instruction{action: UnregisteredAction}}
        ])

      state = %{state | router: router}

      signal = Signal.new!(%{type: "invalid_action", data: %{}})
      assert {:error, _reason} = Runtime.execute(state, signal)
    end
  end
end
