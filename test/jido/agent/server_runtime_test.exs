defmodule JidoTest.Agent.Server.RuntimeTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Runtime
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestActions

  @moduletag :capture_log

  setup do
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = BasicAgent.new("test")

    # Register ErrorAction with the agent for error testing
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.ErrorAction)

    state = %ServerState{
      agent: agent,
      child_supervisor: supervisor,
      dispatch: {:pid, [target: self(), delivery_mode: :async]},
      status: :idle,
      pending_signals: :queue.new()
    }

    {:ok, state: state}
  end

  describe "run_agent_instructions/2" do
    test "successfully executes empty queue", %{state: state} do
      # Start with empty queue
      assert {:ok, final_state} = Runtime.run_agent_instructions(state)
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end

    test "executes single instruction in queue", %{state: state} do
      # Plan a single instruction
      {:ok, agent_with_instruction} =
        state.agent.__struct__.plan(state.agent, {TestActions.NoSchema, %{value: 1}})

      state = %{state | agent: agent_with_instruction}

      # Execute all instructions
      assert {:ok, final_state} = Runtime.run_agent_instructions(state)

      # Verify results
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.agent.pending_instructions)
      # NoSchema adds 2 to input value
      assert final_state.agent.state.result == 3
    end

    test "executes multiple instructions in queue", %{state: state} do
      # Plan multiple instructions
      {:ok, agent} =
        state.agent.__struct__.plan(state.agent, [
          {TestActions.NoSchema, %{value: 1}},
          {TestActions.NoSchema, %{value: 2}},
          {TestActions.NoSchema, %{value: 3}}
        ])

      state = %{state | agent: agent}

      # Execute all instructions
      assert {:ok, final_state} = Runtime.run_agent_instructions(state)

      # Verify results
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.agent.pending_instructions)
      # Last NoSchema adds 2 to input value 3
      assert final_state.agent.state.result == 5
    end

    test "handles errors in instruction execution", %{state: state} do
      # Plan an instruction that will fail
      {:ok, agent} =
        state.agent.__struct__.plan(state.agent, [
          {TestActions.NoSchema, %{value: 1}},
          {TestActions.ErrorAction, %{error_type: :runtime}},
          {TestActions.NoSchema, %{value: 3}}
        ])

      state = %{state | agent: agent}

      # Execute should return error
      assert {:error, error} = Runtime.run_agent_instructions(state)
      assert error.message =~ "Runtime error"

      # Queue should still have remaining instructions
      assert :queue.len(state.agent.pending_instructions) == 3
    end

    test "returns error for invalid initial state", %{state: state} do
      # Try to execute from an invalid state
      invalid_state = %{state | status: :error}

      assert {:error, {:invalid_state, :error}} = Runtime.run_agent_instructions(invalid_state)
    end

    test "executes with custom options", %{state: state} do
      # Plan instruction
      {:ok, agent} = state.agent.__struct__.plan(state.agent, {TestActions.NoSchema, %{value: 1}})
      state = %{state | agent: agent}

      # Execute with apply_state: false
      assert {:ok, final_state} = Runtime.run_agent_instructions(state, apply_state: false)

      # Result should be stored but state shouldn't be updated
      # NoSchema adds 2 to input value
      assert final_state.agent.result == %{result: 3}
      refute Map.get(final_state.agent.state, :result) == 3
    end

    test "executes dynamically enqueued instructions via directives", %{state: state} do
      # Plan an EnqueueAction that will add a NoSchema action to the queue
      {:ok, agent} =
        state.agent.__struct__.plan(state.agent, [
          # First set an initial value
          {TestActions.NoSchema, %{value: 1}},
          # Then enqueue another action that will process that value
          {TestActions.EnqueueAction,
           %{
             action: TestActions.NoSchema,
             # This will add 2 to make it 5
             params: %{value: 3},
             opts: %{apply_state: true}
           }}
        ])

      state = %{state | agent: agent}

      # Execute all instructions (including dynamically added ones)
      assert {:ok, final_state} = Runtime.run_agent_instructions(state)

      # Verify results
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.agent.pending_instructions)

      # The final result should be from the dynamically added NoSchema action
      # which added 2 to the input value of 3
      assert final_state.agent.state.result == 5
    end
  end
end
