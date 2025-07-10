defmodule Jido.CallbackBehaviorComplianceTest do
  @moduledoc """
  CRITICAL: These tests MUST FAIL before fixes are applied and PASS after fixes.
  
  This test suite reproduces callback behavior contract violations that occur when
  the macro-generated code doesn't properly align with the defined behavior specifications.
  These violations happen because the generated callbacks receive different parameter
  types than what the behavior contracts specify.
  
  The tests verify that callback contract mismatches are reproducible and will validate
  that fixes properly align the generated code with behavior specifications.
  """

  use ExUnit.Case, async: false

  # Agent with comprehensive callback implementations to test behavior contracts
  defmodule CallbackTestAgent do
    use Jido.Agent,
      name: "callback_test_agent",
      description: "Agent for testing callback behavior compliance",
      schema: [
        status: [type: :atom, default: :idle],
        callback_count: [type: :integer, default: 0],
        errors: [type: {:list, :any}, default: []],
        metadata: [type: :map, default: %{}]
      ]

    # Implement all possible callbacks to test behavior contract alignment
    def mount(agent, opts) do
      # The behavior expects: mount(agent :: t(), opts :: keyword()) :: agent_result()
      # But may receive different types, causing contract violations
      updated_metadata = Map.put(agent.state.metadata, :mounted, true)
      updated_metadata = Map.put(updated_metadata, :mount_opts, opts)
      
      {:ok, %{agent | state: %{agent.state | metadata: updated_metadata}}}
    end

    def shutdown(agent, reason) do
      # The behavior expects: shutdown(agent :: t(), reason :: any()) :: agent_result()
      # Contract violations may occur with parameter type mismatches
      updated_metadata = Map.put(agent.state.metadata, :shutdown_reason, reason)
      
      {:ok, %{agent | state: %{agent.state | metadata: updated_metadata}}}
    end

    def on_before_validate_state(agent) do
      # The behavior expects: on_before_validate_state(agent :: t()) :: agent_result()
      # May trigger type violations if agent parameter type doesn't match
      count = agent.state.callback_count + 1
      {:ok, %{agent | state: %{agent.state | callback_count: count}}}
    end

    def on_after_validate_state(agent) do
      # The behavior expects: on_after_validate_state(agent :: t()) :: agent_result()
      # Similar potential for type contract violations
      updated_metadata = Map.put(agent.state.metadata, :validated, true)
      {:ok, %{agent | state: %{agent.state | metadata: updated_metadata}}}
    end

    def on_before_plan(agent, instructions, params) do
      # The behavior expects: on_before_plan(agent :: t(), instructions :: any(), params :: any()) :: agent_result()
      # Complex parameter handling may trigger multiple type violations
      planning_data = %{
        instructions: instructions,
        params: params,
        planned_at: DateTime.utc_now()
      }
      
      updated_metadata = Map.put(agent.state.metadata, :planning, planning_data)
      {:ok, %{agent | state: %{agent.state | metadata: updated_metadata}}}
    end

    def on_before_run(agent) do
      # The behavior expects: on_before_run(agent :: t()) :: agent_result()
      # Type contract violations likely when agent struct type doesn't align
      {:ok, %{agent | state: %{agent.state | status: :running}}}
    end

    def on_after_run(agent, result, metadata) do
      # The behavior expects: on_after_run(agent :: t(), result :: any(), metadata :: any()) :: agent_result()
      # Multiple parameters increase chance of type contract violations
      run_data = %{
        result: result,
        metadata: metadata,
        completed_at: DateTime.utc_now()
      }
      
      updated_metadata = Map.put(agent.state.metadata, :last_run, run_data)
      {:ok, %{agent | state: %{agent.state | status: :completed, metadata: updated_metadata}}}
    end

    def on_error(agent, error) do
      # The behavior expects: on_error(agent :: t(), error :: any()) :: agent_result()
      # Error parameter type handling may cause contract violations
      updated_errors = [error | agent.state.errors]
      updated_metadata = Map.put(agent.state.metadata, :last_error, error)
      
      {:ok, %{agent | state: %{
        agent.state | 
        errors: updated_errors, 
        metadata: updated_metadata,
        status: :error
      }}}
    end
  end

  # Minimal agent to test basic callback contract issues
  defmodule MinimalCallbackAgent do
    use Jido.Agent,
      name: "minimal_callback_agent",
      description: "Minimal agent for basic callback testing",
      schema: [
        value: [type: :integer, default: 0]
      ]

    # Only implement mount to test specific contract violation
    def mount(agent, opts) do
      # This should match behavior but may trigger type violations
      # when macro-generated code passes wrong parameter types
      {:ok, %{agent | state: %{agent.state | value: Keyword.get(opts, :initial_value, 0)}}}
    end
  end

  describe "Callback Behavior Contract Violation #1: mount/2 callback keyword violations" do
    test "reproduces mount callback Keyword.get violations with map opts" do
      # This test reproduces the pattern where callback implementations call
      # Keyword.get/3 but receive maps instead of keyword lists, causing the
      # core FunctionClauseError that we need to fix
      
      agent = MinimalCallbackAgent.new()
      
      # Case 1: Keyword list opts (should work)
      result1 = MinimalCallbackAgent.mount(agent, [initial_value: 42])
      assert {:ok, mounted_agent} = result1
      assert mounted_agent.state.value == 42
      
      # Case 2: Map opts (should work but triggers FunctionClauseError at Keyword.get/3)
      # This is the core type violation we're testing
      result2 = MinimalCallbackAgent.mount(agent, %{initial_value: 100})
      assert {:ok, mounted_agent2} = result2
      assert mounted_agent2.state.value == 100
      
      # Case 3: Another map variation
      result3 = MinimalCallbackAgent.mount(agent, %{initial_value: 999})
      assert {:ok, mounted_agent3} = result3
      assert mounted_agent3.state.value == 999
    end
  end

  describe "Callback Behavior Contract Violation #2: set/3 function macro violations" do
    test "reproduces set/3 type violations when calling with map opts" do
      # The REAL core issue is in the macro-generated set/3 function that calls
      # Keyword.get/3 but receives maps, causing FunctionClauseError
      
      agent = CallbackTestAgent.new()
      
      # Case 1: Map opts trigger the core violation
      result1 = CallbackTestAgent.set(agent, %{status: :test1}, %{validation: true})
      assert {:ok, _} = result1
      
      # Case 2: Another map opts variation
      result2 = CallbackTestAgent.set(agent, %{callback_count: 5}, %{strict_mode: false})
      assert {:ok, _} = result2
      
      # Case 3: Complex map opts
      result3 = CallbackTestAgent.set(agent, %{metadata: %{test: true}}, %{complex: %{nested: :opts}})
      assert {:ok, _} = result3
    end

    test "reproduces set/3 violations with MinimalCallbackAgent" do
      # Test the same pattern with the minimal agent
      
      agent = MinimalCallbackAgent.new()
      
      # Case 1: Map opts trigger the violation
      result1 = MinimalCallbackAgent.set(agent, %{value: 42}, %{validation: true})
      assert {:ok, _} = result1
      
      # Case 2: Another variation
      result2 = MinimalCallbackAgent.set(agent, %{value: 100}, %{strict_validation: false})
      assert {:ok, _} = result2
    end
  end
end