defmodule Jido.GeneratedFunctionContractsTest do
  @moduledoc """
  CRITICAL: These tests MUST FAIL before fixes are applied and PASS after fixes.
  
  This test suite reproduces type specification violations in the macro-generated
  functions created by the Jido.Agent.__using__/1 macro. These violations occur
  when the generated functions have type specifications that don't match their
  actual implementation behavior.
  
  The tests verify that contract violations are reproducible and will validate
  that fixes properly align the generated function specifications with their
  actual behavior.
  """

  use ExUnit.Case, async: false

  # Agent for testing basic generated function contracts
  defmodule ContractTestAgent do
    use Jido.Agent,
      name: "contract_test_agent",
      description: "Agent for testing generated function contract violations",
      schema: [
        name: [type: :string, default: "test_agent"],
        enabled: [type: :boolean, default: true],
        config: [type: :map, default: %{}],
        items: [type: {:list, :any}, default: []]
      ]
  end

  # Agent with strict validation for testing edge cases
  defmodule StrictContractAgent do
    use Jido.Agent,
      name: "strict_contract_agent",
      description: "Agent with strict validation for contract testing",
      schema: [
        id: [type: :integer, required: true],
        data: [type: :map, default: %{}],
        metadata: [type: :map, default: %{}]
      ]
  end

  describe "Generated Function Contract Violation #1: set/3 function specifications" do
    test "reproduces set/3 parameter type specification violations" do
      agent = ContractTestAgent.new()
      
      # The set/3 function has type specification: (t(), keyword() | map(), keyword()) -> agent_result()
      # But the implementation calls Keyword.get/3 on the opts parameter, which fails
      # when opts is a map instead of keyword list
      
      # These are various opts parameter types that trigger the violation
      opts_variations = [
        # Maps instead of keyword lists (triggers FunctionClauseError)
        %{validate: true},
        %{strict_validation: false, debug: true},
        %{custom_opts: %{nested: true}},
        %{timeout: 5000, async: false},
        %{mode: :test, source: :contract_test}
      ]
      
      Enum.each(opts_variations, fn opts ->
        # Each variation triggers the FunctionClauseError at Keyword.get/3
        result = ContractTestAgent.set(agent, %{name: "test"}, opts)
        assert {:ok, _} = result
      end)
    end

    test "reproduces recursive set/3 call type violations" do
      agent = ContractTestAgent.new()
      
      # Test the specific pattern where set/3 calls itself recursively
      # with transformed parameters that may violate type contracts
      
      # This triggers the recursive call pattern in the generated code
      result1 = ContractTestAgent.set(agent, %{config: %{updated: true}}, %{recursive: true})
      assert {:ok, _} = result1
      
      result2 = ContractTestAgent.set(agent, %{items: [1, 2, 3]}, %{depth: 2})
      assert {:ok, _} = result2
    end
  end

  describe "Generated Function Contract Violation #2: validate/2 specifications" do
    test "reproduces validate/2 parameter and return type violations" do
      # Create agent with valid data to avoid schema validation errors
      agent = %StrictContractAgent{StrictContractAgent.new() | state: %{id: 42, data: %{}, metadata: %{}}}
      
      # The validate/2 function may have parameter type specifications that
      # don't align with the actual parameter handling in the implementation
      
      # Case 1: Standard opts parameter (should work)
      result1 = StrictContractAgent.validate(agent, [strict: true])
      assert {:ok, _} = result1
      
      # Case 2: Map opts parameter (triggers FunctionClauseError at Keyword.get/3)
      result2 = StrictContractAgent.validate(agent, %{strict: false, custom: true})
      assert {:ok, _} = result2
      
      # Case 3: More map opts variations to trigger violations
      result3 = StrictContractAgent.validate(agent, %{validation_mode: :strict})
      assert {:ok, _} = result3
      
      result4 = StrictContractAgent.validate(agent, %{debug: true, custom_validation: false})
      assert {:ok, _} = result4
    end
  end

  describe "Generated Function Contract Violation #3: Additional set/3 violations" do
    test "reproduces additional set/3 map opts violations" do
      agent = ContractTestAgent.new()
      
      # More variations of the core set/3 type violation to ensure comprehensive coverage
      result1 = ContractTestAgent.set(agent, %{name: "test"}, %{mode: :violation})
      assert {:ok, _} = result1
      
      result2 = ContractTestAgent.set(agent, %{config: %{nested: true}}, %{validation: false, debug: true})
      assert {:ok, _} = result2
      
      result3 = ContractTestAgent.set(agent, %{items: [1, 2, 3]}, %{type: :list_update})
      assert {:ok, _} = result3
      
      result4 = ContractTestAgent.set(agent, %{enabled: false}, %{reason: :testing, force: true})
      assert {:ok, _} = result4
    end
  end
end