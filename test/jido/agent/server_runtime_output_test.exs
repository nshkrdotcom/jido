defmodule JidoTest.Agent.Server.RuntimeOutputTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Server.{Runtime, State}
  alias Jido.{Agent, Instruction}
  alias Jido.Signal
  alias Jido.Signal.Router
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestActions
  alias Jido.Agent.Server.Signal, as: ServerSignal

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
    test "executes instructions and returns result", %{state: state} do
      instruction = %Instruction{id: "test", action: TestActions.NoSchema, params: %{value: 1}}

      assert {:ok, final_state, %{result: 3}} =
               Runtime.execute_agent_instructions(state, [instruction])

      assert final_state.agent.result == %{result: 3}
    end

    test "handles empty instruction list", %{state: state} do
      assert {:ok, final_state, nil} = Runtime.execute_agent_instructions(state, [])
      assert final_state.agent.result == nil
    end

    test "preserves correlation id through execution", %{state: state} do
      state = %{state | current_correlation_id: "test-correlation"}
      instruction = %Instruction{id: "test", action: TestActions.NoSchema, params: %{value: 1}}

      assert {:ok, final_state, _result} =
               Runtime.execute_agent_instructions(state, [instruction])

      assert final_state.current_correlation_id == "test-correlation"
    end

    test "handles errors during execution", %{state: state} do
      instruction = %Instruction{id: "test", action: TestActions.ErrorAction, params: %{}}
      assert {:error, _reason} = Runtime.execute_agent_instructions(state, [instruction])
    end
  end

  describe "handle_cmd_result/3" do
    test "returns {:ok, state} if the command result is successful", %{state: state} do
      agent = %{state.agent | result: :ok}
      assert {:ok, _state} = Runtime.handle_cmd_result(state, agent, [])
    end

    test "emits output with correct correlation and causation IDs", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id}
      agent = %{state.agent | result: %{value: "test result"}}

      {:ok, _state} = Runtime.handle_cmd_result(state, agent, [])

      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))
      assert signal.data == %{value: "test result"}
      assert signal.jido_correlation_id == correlation_id
    end
  end

  describe "handle_agent_instruction_result/3" do
    test "returns {:ok, state} if the agent instruction result is successful", %{state: state} do
      assert {:ok, _updated_state} = Runtime.handle_agent_instruction_result(state, :ok, [])
    end

    test "emits output with correct correlation and causation IDs", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id}
      result = %{value: "test result"}

      {:ok, _state} = Runtime.handle_agent_instruction_result(state, result, [])

      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))
      assert signal.data == %{value: "test result"}
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
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:out, :signal_result}))
      assert signal.data == %{value: "test result"}
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
end
