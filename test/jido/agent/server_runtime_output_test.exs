defmodule JidoTest.Agent.Server.RuntimeOutputTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Server.{Runtime, State}
  alias Jido.{Agent, Instruction}
  alias Jido.Signal
  alias Jido.Signal.Router
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestActions

  @moduletag :capture_log
  @moduletag timeout: 30000

  # Mock the Agent module's run function
  defmodule MockAgent do
    def run(%Agent{} = agent, _opts) do
      case :queue.peek(agent.pending_instructions) do
        :empty ->
          {:ok, agent, []}

        {:value, %Instruction{action: TestActions.ErrorAction}} ->
          {:error, "Test error"}

        _ ->
          {:ok, agent, []}
      end
    end
  end

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

    state = %State{
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

  describe "run_agent_instructions/2" do
    test "executes instructions and returns result", %{state: state} do
      state = %{state | status: :idle}

      instruction =
        Instruction.new!(%{id: "test", action: TestActions.NoSchema, params: %{value: 1}})

      agent = %{state.agent | pending_instructions: :queue.from_list([instruction])}
      state = %{state | agent: agent}

      assert {:ok, final_state, %{result: 3}} = Runtime.run_agent_instructions(state)
      assert final_state.status == :idle
      assert :queue.len(final_state.agent.pending_instructions) == 0
    end

    test "handles empty instruction queue", %{state: state} do
      state = %{state | status: :idle}
      agent = %{state.agent | pending_instructions: :queue.new(), result: :no_instructions}
      state = %{state | agent: agent}

      assert {:ok, final_state, :no_instructions} = Runtime.run_agent_instructions(state)
      assert final_state.status == :idle
    end

    test "transitions from running to idle when complete", %{state: state} do
      state = %{state | status: :running}
      agent = %{state.agent | pending_instructions: :queue.new(), result: :done}
      state = %{state | agent: agent}

      assert {:ok, final_state, :done} = Runtime.run_agent_instructions(state)
      assert final_state.status == :idle
    end

    test "preserves correlation id through execution", %{state: state} do
      state = %{state | status: :idle, current_correlation_id: "test-correlation"}
      instruction = %Instruction{id: "test", action: TestActions.NoSchema, params: %{value: 1}}
      agent = %{state.agent | pending_instructions: :queue.from_list([instruction])}
      state = %{state | agent: agent}

      assert {:ok, final_state, %{result: 3}} = Runtime.run_agent_instructions(state)
      assert final_state.current_correlation_id == "test-correlation"
    end

    test "handles errors during execution", %{state: state} do
      state = %{state | status: :idle}
      instruction = %Instruction{id: "test", action: TestActions.ErrorAction, params: %{}}
      agent = %{state.agent | pending_instructions: :queue.from_list([instruction])}
      state = %{state | agent: agent}

      assert {:error, _reason} = Runtime.run_agent_instructions(state)
    end
  end

  describe "do_execute_all_instructions/2" do
    test "executes all instructions in queue", %{state: state} do
      state = %{state | status: :running}

      instructions = [
        %Instruction{id: "test1", action: TestActions.NoSchema, params: %{value: 1}},
        %Instruction{id: "test2", action: TestActions.NoSchema, params: %{value: 2}}
      ]

      agent = %{state.agent | pending_instructions: :queue.from_list(instructions)}
      state = %{state | agent: agent}

      assert {:ok, final_state, %{result: 4}} = Runtime.do_execute_all_instructions(state, [])
      assert final_state.status == :idle
      assert :queue.len(final_state.agent.pending_instructions) == 0
    end

    test "stops on first error", %{state: state} do
      state = %{state | status: :running}

      instructions = [
        %Instruction{id: "test1", action: TestActions.NoSchema, params: %{value: 1}},
        %Instruction{id: "error", action: TestActions.ErrorAction, params: %{}}
      ]

      agent = %{state.agent | pending_instructions: :queue.from_list(instructions)}
      state = %{state | agent: agent}

      assert {:error, _reason} = Runtime.do_execute_all_instructions(state, [])
    end

    test "handles empty queue", %{state: state} do
      state = %{state | status: :running}
      agent = %{state.agent | pending_instructions: :queue.new(), result: :empty}
      state = %{state | agent: agent}

      assert {:ok, final_state, :empty} = Runtime.do_execute_all_instructions(state, [])
      assert final_state.status == :idle
    end

    test "preserves correlation id", %{state: state} do
      state = %{state | status: :running, current_correlation_id: "test-correlation"}
      instruction = %Instruction{id: "test", action: TestActions.NoSchema, params: %{value: 1}}
      agent = %{state.agent | pending_instructions: :queue.from_list([instruction])}
      state = %{state | agent: agent}

      assert {:ok, final_state, %{result: 3}} = Runtime.do_execute_all_instructions(state, [])
      assert final_state.current_correlation_id == "test-correlation"
    end
  end

  describe "handle_cmd_result/3" do
    test "returns {:ok, state} if the command result is successful", %{state: state} do
      agent = %{state.agent | result: :ok}
      assert {:ok, _state} = Runtime.handle_cmd_result(state, agent, [])

      # Should receive the agent result signal
      assert_receive {:signal, signal}
      assert signal.type == "jido.agent.out"
      assert signal.data == {:ok, :ok}
    end

    test "processes directives and emits signals", %{state: state} do
      task = fn -> Process.sleep(1000) end
      agent = %{state.agent | result: %{value: "test result"}}
      directives = [%Jido.Agent.Directive.Spawn{module: Task, args: task}]

      {:ok, _state} = Runtime.handle_cmd_result(state, agent, directives)

      # First receive the agent result signal
      assert_receive {:signal, result_signal}
      assert result_signal.type == "jido.agent.out"
      assert result_signal.data == {:ok, %{value: "test result"}}

      # Then receive the process_started signal from directive
      assert_receive {:signal, directive_signal}
      assert directive_signal.type == "jido.agent.event.process.started"
      assert is_pid(directive_signal.data.child_pid)
    end

    test "handles multiple directives in sequence", %{state: state} do
      task1 = fn -> Process.sleep(1000) end
      task2 = fn -> Process.sleep(1000) end
      agent = %{state.agent | result: :ok}

      directives = [
        %Jido.Agent.Directive.Spawn{module: Task, args: task1},
        %Jido.Agent.Directive.Spawn{module: Task, args: task2}
      ]

      {:ok, _state} = Runtime.handle_cmd_result(state, agent, directives)

      # First receive the agent result signal
      assert_receive {:signal, result_signal}
      assert result_signal.type == "jido.agent.out"
      assert result_signal.data == {:ok, :ok}

      # Then receive signals for both spawned processes
      assert_receive {:signal, signal1}
      assert signal1.type == "jido.agent.event.process.started"
      assert is_pid(signal1.data.child_pid)

      assert_receive {:signal, signal2}
      assert signal2.type == "jido.agent.event.process.started"
      assert is_pid(signal2.data.child_pid)
    end

    test "stops processing on first directive error", %{state: state} do
      task = fn -> Process.sleep(1000) end
      agent = %{state.agent | result: :ok}

      directives = [
        %Jido.Agent.Directive.Spawn{module: Task, args: task},
        :invalid_directive
      ]

      {:error, error} = Runtime.handle_cmd_result(state, agent, directives)

      # First receive the agent result signal
      assert_receive {:signal, result_signal}
      assert result_signal.type == "jido.agent.out"
      assert result_signal.data == {:ok, :ok}

      # Then receive the process_started signal
      assert_receive {:signal, signal}
      assert signal.type == "jido.agent.event.process.started"
      assert is_pid(signal.data.child_pid)

      # No more signals after error
      refute_receive {:signal, _}

      assert %Jido.Error{} = error
      assert error.type == :validation_error
      assert error.message == "Invalid directive"
      assert error.details == %{directive: :invalid_directive}
    end

    test "preserves correlation ID through directive processing", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id}

      task = fn -> Process.sleep(1000) end
      agent = %{state.agent | result: %{value: "test result"}}
      directives = [%Jido.Agent.Directive.Spawn{module: Task, args: task}]

      {:ok, _state} = Runtime.handle_cmd_result(state, agent, directives)

      # First check result signal
      assert_receive {:signal, result_signal}
      assert result_signal.type == "jido.agent.out"
      assert result_signal.data == {:ok, %{value: "test result"}}
      assert result_signal.jido_correlation_id == correlation_id

      # Then check directive signal
      assert_receive {:signal, directive_signal}
      assert directive_signal.type == "jido.agent.event.process.started"
      assert directive_signal.jido_correlation_id == correlation_id
    end
  end

  describe "handle_agent_step_result/3" do
    test "returns {:ok, state} if the agent step result is successful", %{state: state} do
      assert {:ok, _updated_state} = Runtime.handle_agent_step_result(state, :ok, [])
    end

    test "emits output with correct correlation and causation IDs", %{state: state} do
      correlation_id = "test-correlation-id"
      causation_id = "test-causation-id"

      state = %{state | current_correlation_id: correlation_id}
      result = %{value: "test result"}

      {:ok, _state} = Runtime.handle_agent_step_result(state, result, causation_id: causation_id)

      assert_receive {:signal, signal}
      assert signal.type == "jido.agent.out"
      assert signal.data == {:ok, %{value: "test result"}}
      assert signal.jido_correlation_id == correlation_id
      assert signal.jido_causation_id == causation_id
    end

    test "handles nil result with correlation ID", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id}

      {:ok, _state} = Runtime.handle_agent_step_result(state, nil, [])

      assert_receive {:signal, signal}
      assert signal.type == "jido.agent.out"
      assert signal.data == {:ok, nil}
      assert signal.jido_correlation_id == correlation_id
    end

    test "preserves complex result structures", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id}

      result = %{
        nested: %{
          value: "test",
          list: [1, 2, 3]
        }
      }

      {:ok, _state} = Runtime.handle_agent_step_result(state, result, [])

      assert_receive {:signal, signal}
      assert signal.type == "jido.agent.out"

      assert signal.data ==
               {:ok,
                %{
                  nested: %{
                    value: "test",
                    list: [1, 2, 3]
                  }
                }}

      assert signal.jido_correlation_id == correlation_id
    end
  end

  describe "handle_agent_final_result/3" do
    test "returns {:ok, state, result} if the agent result is successful", %{state: state} do
      agent = %{state.agent | result: :ok}
      state = %{state | agent: agent}

      assert {:ok, new_state, :ok} = Runtime.handle_agent_final_result(state, :ok)
      assert new_state.status == :idle
    end

    test "preserves correlation ID through execution", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id}
      agent = %{state.agent | result: %{value: "test result"}}
      state = %{state | agent: agent}

      {:ok, _new_state, _result} =
        Runtime.handle_agent_final_result(state, %{value: "test result"})

      assert_receive {:signal, signal}
      assert signal.type == "jido.agent.out"
      assert signal.data == {:ok, %{value: "test result"}}
      assert signal.jido_correlation_id == correlation_id
    end
  end

  describe "apply_signal_to_first_instruction/2" do
    test "merges signal data into first instruction params" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})
      instruction = Instruction.new!(%{action: TestActions.NoSchema, params: %{baz: "qux"}})

      assert {:ok, [result | _]} =
               Runtime.apply_signal_to_first_instruction(signal, [instruction])

      assert result.params == %{foo: "bar", baz: "qux"}
    end

    test "handles nil params in instruction" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})
      instruction = Instruction.new!(%{action: TestActions.NoSchema, params: nil})

      assert {:ok, [result | _]} =
               Runtime.apply_signal_to_first_instruction(signal, [instruction])

      assert result.params == %{foo: "bar"}
    end

    test "handles nil data in signal" do
      signal = Signal.new!(%{type: "test", data: nil})
      instruction = Instruction.new!(%{action: TestActions.NoSchema, params: %{baz: "qux"}})

      assert {:ok, [result | _]} =
               Runtime.apply_signal_to_first_instruction(signal, [instruction])

      assert result.params == %{baz: "qux"}
    end

    test "returns ok with empty list for empty instructions" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})

      assert {:ok, []} = Runtime.apply_signal_to_first_instruction(signal, [])
    end

    test "returns error for invalid instruction" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})

      assert {:error, :invalid_instruction} =
               Runtime.apply_signal_to_first_instruction(signal, [:not_an_instruction])
    end

    test "returns error if merging params fails" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})

      instruction = :not_an_instruction

      assert {:error, :invalid_instruction} =
               Runtime.apply_signal_to_first_instruction(signal, [instruction])
    end
  end

  describe "ensure_running_state/1" do
    test "transitions idle state to running", %{state: state} do
      assert state.status == :idle
      assert {:ok, new_state} = Runtime.ensure_running_state(state)
      assert new_state.status == :running
    end

    test "keeps running state as running", %{state: state} do
      # First transition to running
      {:ok, running_state} = Runtime.ensure_running_state(state)
      assert running_state.status == :running

      # Should stay running
      assert {:ok, still_running} = Runtime.ensure_running_state(running_state)
      assert still_running.status == :running
    end

    test "returns error for invalid states", %{state: state} do
      invalid_state = %{state | status: :invalid}
      assert {:error, {:invalid_state, :invalid}} = Runtime.ensure_running_state(invalid_state)
    end
  end
end
