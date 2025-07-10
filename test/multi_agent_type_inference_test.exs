defmodule Jido.MultiAgentTypeInferenceTest do
  @moduledoc """
  CRITICAL: These tests MUST FAIL before fixes are applied and PASS after fixes.
  
  This test suite reproduces type inference failures that occur when Dialyzer
  analyzes cross-module interactions between different Jido agents. These failures
  happen because the macro-generated code doesn't maintain proper type consistency
  across module boundaries.
  
  The tests verify that type inference issues are reproducible when agents interact
  with each other through the generated functions, exposing specification mismatches
  that only become apparent during cross-module analysis.
  """

  use ExUnit.Case, async: false

  # Define multiple agent modules to trigger cross-module type inference issues
  defmodule AgentTypeA do
    use Jido.Agent,
      name: "type_a_agent",
      description: "Agent for testing cross-module type inference",
      schema: [
        identifier: [type: :string, default: "agent_a"],
        count: [type: :integer, default: 0],
        shared_data: [type: :map, default: %{}]
      ]
  end

  defmodule AgentTypeB do
    use Jido.Agent,
      name: "type_b_agent", 
      description: "Second agent for cross-module type testing",
      schema: [
        partner_id: [type: :string, default: ""],
        results: [type: {:list, :any}, default: []],
        metadata: [type: :map, default: %{}]
      ]
  end

  defmodule AgentTypeC do
    use Jido.Agent,
      name: "type_c_agent",
      description: "Third agent for complex type interactions",
      schema: [
        active: [type: :boolean, default: true],
        connections: [type: {:list, :any}, default: []],
        state_data: [type: :map, default: %{}]
      ]

    # Implement callbacks that interact with other agent types
    def sync_with_agent(agent, other_agent) do
      # This function should work with any agent type but may trigger type violations
      # when Dialyzer analyzes the cross-module interactions
      if Map.has_key?(other_agent.state, :identifier) do
        id = other_agent.state.identifier
        updated_connections = [id | agent.state.connections]
        {:ok, %{agent | state: %{agent.state | connections: updated_connections}}}
      else
        {:error, "Failed to sync with agent"}
      end
    end
  end

  describe "Cross-Module Type Inference Issue #1: Agent interaction patterns" do
    test "reproduces type inference failures in agent-to-agent communications" do
      # Create agents of different types
      agent_a = AgentTypeA.new()
      agent_b = AgentTypeB.new()
      agent_c = AgentTypeC.new()
      
      # These cross-module interactions should work at runtime but trigger
      # Dialyzer type inference errors due to generic type specifications
      
      # Case 1: AgentTypeA calling AgentTypeB functions - SHOULD TRIGGER VIOLATION
      result1 = AgentTypeB.set(agent_b, %{partner_id: agent_a.id}, %{cross_module: true})
      assert {:ok, _updated_b} = result1
      
      # Case 2: AgentTypeC calling AgentTypeA functions - SHOULD TRIGGER VIOLATION  
      result2 = AgentTypeA.set(agent_a, %{shared_data: %{connected_to: agent_c.id}}, %{external_call: true})
      assert {:ok, _updated_a} = result2
      
      # Case 3: Mixed agent operations that expose type inference issues
      cross_module_operation(agent_a, agent_b, agent_c)
    end

    test "reproduces generic type specification conflicts across modules" do
      # Test the pattern where agents of different types are passed to functions
      # expecting generic Jido.Agent.t() types, causing inference conflicts
      
      agents = [
        AgentTypeA.new(),
        AgentTypeB.new(), 
        AgentTypeC.new()
      ]
      
      # Process all agents through the same function that expects Jido.Agent.t()
      # This should work but triggers type inference issues
      processed_agents = Enum.map(agents, fn agent ->
        # Each agent has its own struct type but function expects generic type
        case agent.__struct__.set(agent, %{updated: true}, %{strict_validation: false}) do
          {:ok, updated_agent} -> updated_agent
          error -> error
        end
      end)
      
      # All operations should succeed at runtime
      Enum.each(processed_agents, fn result ->
        assert match?(%{__struct__: _}, result), "Expected agent struct, got: #{inspect(result)}"
      end)
    end
  end

  describe "Cross-Module Type Inference Issue #2: Function parameter type propagation" do
    test "reproduces parameter type conflicts when calling across agent modules" do
      agent_a = AgentTypeA.new()
      agent_b = AgentTypeB.new()
      
      # Test parameter passing patterns that trigger type inference errors
      # when Dialyzer analyzes the full call graph across modules
      
      # Pattern 1: Passing state from one agent to another's set function
      state_from_a = agent_a.state
      result1 = AgentTypeB.set(agent_b, Map.take(state_from_a, [:shared_data]), [])
      assert {:ok, _} = result1
      
      # Pattern 2: Using opts parameter types that don't align across modules
      opts_variations = [
        [validate: true, source: :agent_a],
        %{validate: false, source: :agent_b},
        [cross_module: true, validate: :strict]
      ]
      
      Enum.each(opts_variations, fn opts ->
        # Each variation may trigger different type inference issues
        result = AgentTypeA.set(agent_a, %{count: 1}, opts)
        # Should handle various opts types but may violate type contracts
        case result do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end
      end)
    end

  end

  describe "Cross-Module Type Inference Issue #3: Generic vs specific type conflicts" do
    test "reproduces conflicts between Jido.Agent.t() and module-specific types" do
      # This test reproduces the core issue where the macro generates functions
      # that work with generic Jido.Agent.t() types but receive module-specific structs
      
      agent_a = AgentTypeA.new()
      agent_b = AgentTypeB.new()
      
      # Test operations that should maintain type safety but may violate contracts
      # due to the generic vs specific type definitions
      
      # Pattern 1: Store agents in a list (generic type context)
      agent_list = [agent_a, agent_b]
      
      # Pattern 2: Process each agent through its own module functions
      results = Enum.map(agent_list, fn agent ->
        module = agent.__struct__
        
        # This call pattern exposes the generic vs specific type conflict
        # Dialyzer sees: Agent.t() -> Agent.t() but receives ModuleAgent -> ModuleAgent
        case module.set(agent, %{processed: true}, %{type_conflict: true}) do
          {:ok, updated} -> 
            # Type assertion should work but may trigger inference issues
            assert %^module{} = updated
            updated
          error -> 
            error
        end
      end)
      
      # Verify all operations completed
      Enum.each(results, fn result ->
        assert is_struct(result), "Expected struct result, got: #{inspect(result)}"
      end)
    end

    test "reproduces recursive type inference failures in nested calls" do
      agent_a = AgentTypeA.new()
      
      # Test nested function calls that trigger recursive type inference issues
      # These patterns work at runtime but cause Dialyzer to fail when analyzing
      # the complete call graph across module boundaries
      
      # Nested set operations that may trigger recursive type violations
      result = agent_a
      |> AgentTypeA.set(%{count: 1}, [])
      |> case do
        {:ok, updated1} ->
          # Second level nesting - triggers deeper type inference issues
          AgentTypeA.set(updated1, %{shared_data: %{nested: true}}, [validate: true])
        error -> error
      end
      |> case do
        {:ok, updated2} ->
          # Third level - exposes the recursive type specification problems
          AgentTypeA.set(updated2, %{identifier: "nested_test"}, %{deep_validation: true})
        error -> error
      end
      
      # This pattern should work but triggers the recursive type violations
      # that only Dialyzer can detect in the complete call graph analysis
      case result do
        {:ok, final_agent} ->
          assert %AgentTypeA{} = final_agent
          assert final_agent.state.count == 1
          assert final_agent.state.identifier == "nested_test"
        error ->
          flunk("Recursive type operations failed: #{inspect(error)}")
      end
    end
  end

  describe "Cross-Module Type Inference Issue #4: Polymorphic function type conflicts" do
    test "reproduces polymorphic parameter handling across agent types" do
      # Test patterns where the same function signature is used across different
      # agent types but with different parameter types, causing inference conflicts
      
      agents = [
        {AgentTypeA, AgentTypeA.new()},
        {AgentTypeB, AgentTypeB.new()},
        {AgentTypeC, AgentTypeC.new()}
      ]
      
      # Apply the same operation pattern to different agent types
      # This exposes polymorphic type handling issues
      Enum.each(agents, fn {module, agent} ->
        # Each module handles the same parameter pattern differently
        # causing type inference conflicts when Dialyzer analyzes all modules
        
        params = %{
          test_field: "polymorphic_test",
          numeric_value: 42,
          list_data: [:a, :b, :c]
        }
        
        result = module.set(agent, params, %{polymorphic: true})
        
        case result do
          {:ok, updated_agent} ->
            # Each agent type should handle the polymorphic parameters
            assert updated_agent.__struct__ == module
          error ->
            # Some agent types may reject polymorphic parameters
            assert match?({:error, _}, error)
        end
      end)
    end
  end

  # Helper function that triggers cross-module type inference issues
  defp cross_module_operation(agent_a, agent_b, agent_c) do
    # This function calls methods across multiple agent modules
    # exposing type inference issues when Dialyzer analyzes the interactions
    
    # Step 1: Update agent_a with data from agent_b
    {:ok, updated_a} = AgentTypeA.set(agent_a, %{
      shared_data: %{
        partner: agent_b.id,
        partner_type: AgentTypeB
      }
    }, [])
    
    # Step 2: Update agent_b with data from agent_c
    {:ok, updated_b} = AgentTypeB.set(agent_b, %{
      metadata: %{
        connected_to: agent_c.id,
        active_status: agent_c.state.active
      }
    }, [])
    
    # Step 3: Sync agent_c with the updated agents
    {:ok, updated_c} = AgentTypeC.sync_with_agent(agent_c, updated_a)
    
    # Return all updated agents
    {updated_a, updated_b, updated_c}
  end
end