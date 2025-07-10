defmodule Jido.DefensiveBoundaryIntegrationTest do
  @moduledoc """
  CRITICAL: These tests MUST FAIL before fixes are applied and PASS after fixes.

  This test suite reproduces real-world defensive programming patterns that expose
  the Jido type system issues. These tests are based on the patterns from the
  0002_v1_2_0 demo that originally triggered the 37 Dialyzer errors.

  The tests verify that realistic usage patterns expose type violations and will
  validate that fixes enable proper defensive boundary enforcement without
  breaking the type system.
  """

  use ExUnit.Case, async: false

  # Agent that implements defensive boundary patterns from the demo
  defmodule DefensiveBoundaryAgent do
    use Jido.Agent,
      name: "defensive_boundary_agent",
      description: "Agent implementing defensive boundary patterns",
      schema: [
        status: [type: :atom, default: :initializing],
        processing_mode: [type: :atom, default: :safe],
        error_count: [type: :integer, default: 0],
        validated_data: [type: :map, default: %{}],
        security_level: [type: :atom, default: :standard],
        audit_trail: [type: {:list, :any}, default: []]
      ]

    # Defensive validation callback
    def on_before_validate_state(agent) do
      # Implement defensive checks before state validation
      if agent.state.error_count > 10 do
        {:error, "Too many errors, agent disabled"}
      else
        audit_entry = %{
          action: :pre_validation,
          timestamp: DateTime.utc_now(),
          status: agent.state.status
        }

        updated_trail = [audit_entry | agent.state.audit_trail]
        {:ok, %{agent | state: %{agent.state | audit_trail: updated_trail}}}
      end
    end

    # Defensive execution callback
    def on_before_run(agent) do
      # Implement boundary enforcement before execution
      case agent.state.security_level do
        :high ->
          if agent.state.status == :validated do
            {:ok, %{agent | state: %{agent.state | status: :secure_execution}}}
          else
            {:error, "High security requires validated status"}
          end

        :standard ->
          {:ok, %{agent | state: %{agent.state | status: :standard_execution}}}

        :low ->
          {:ok, %{agent | state: %{agent.state | status: :low_security_execution}}}
      end
    end

    # Defensive error handling
    def on_error(agent, error) do
      # Implement defensive error boundary enforcement
      error_count = agent.state.error_count + 1

      audit_entry = %{
        action: :error_handling,
        timestamp: DateTime.utc_now(),
        error: error,
        error_count: error_count
      }

      updated_trail = [audit_entry | agent.state.audit_trail]

      new_status =
        case error_count do
          count when count > 5 -> :error_threshold_exceeded
          count when count > 2 -> :error_monitoring
          _ -> :error_handled
        end

      {:ok,
       %{
         agent
         | state: %{
             agent.state
             | error_count: error_count,
               status: new_status,
               audit_trail: updated_trail
           }
       }}
    end
  end

  # Production-like agent that uses complex defensive patterns
  defmodule ProductionDefensiveAgent do
    use Jido.Agent,
      name: "production_defensive_agent",
      description: "Production-style agent with comprehensive defensive patterns",
      schema: [
        environment: [type: :atom, default: :development],
        resource_limits: [type: :map, default: %{memory: 1024, cpu: 100}],
        active_connections: [type: {:list, :any}, default: []],
        performance_metrics: [type: :map, default: %{}],
        feature_flags: [type: :map, default: %{}],
        configuration: [type: :map, default: %{}]
      ]

    # Complex validation with defensive patterns
    def mount(agent, opts) do
      # Defensive mounting with comprehensive validation
      environment = Keyword.get(opts, :environment, :development)

      if environment == :production do
        # Production requires additional validation
        required_config = [:database_url, :api_keys, :monitoring_endpoint]

        config = Keyword.get(opts, :config, %{})

        missing_config =
          Enum.filter(required_config, fn key ->
            not Map.has_key?(config, key)
          end)

        if Enum.empty?(missing_config) do
          {:ok,
           %{
             agent
             | state: %{
                 agent.state
                 | environment: environment,
                   configuration: config
               }
           }}
        else
          {:error, "Missing required production config: #{inspect(missing_config)}"}
        end
      else
        # Development/test environments are more permissive
        {:ok,
         %{
           agent
           | state: %{
               agent.state
               | environment: environment,
                 configuration: Keyword.get(opts, :config, %{})
             }
         }}
      end
    end

    # Defensive shutdown with cleanup
    def shutdown(agent, reason) do
      # Implement cleanup procedures based on environment and reason
      cleanup_tasks =
        case {agent.state.environment, reason} do
          {:production, :normal} ->
            ["graceful_connection_close", "metrics_flush", "audit_log_write"]

          {:production, _emergency} ->
            ["emergency_state_save", "alert_operations"]

          {_other_env, _any_reason} ->
            ["basic_cleanup"]
        end

      # Record shutdown in performance metrics
      updated_metrics =
        Map.put(agent.state.performance_metrics, :shutdown, %{
          reason: reason,
          timestamp: DateTime.utc_now(),
          cleanup_tasks: cleanup_tasks
        })

      {:ok,
       %{
         agent
         | state: %{
             agent.state
             | performance_metrics: updated_metrics
           }
       }}
    end
  end

  describe "Defensive Boundary Pattern #1: State validation with type enforcement" do
    test "reproduces defensive validation patterns that trigger type violations" do
      # This test reproduces the exact patterns from the demo that triggered
      # the original 37 Dialyzer errors when implementing defensive boundaries

      agent = DefensiveBoundaryAgent.new()

      # Pattern 1: Defensive state updates with validation
      defensive_updates = %{
        status: :validating,
        processing_mode: :strict,
        security_level: :high,
        validated_data: %{
          input_validated: true,
          boundary_checks: ["type_check", "range_check", "permission_check"],
          validation_timestamp: DateTime.utc_now()
        }
      }

      # This pattern triggered type violations in the original demo
      # First test with map opts (triggers type violation)
      result1 =
        DefensiveBoundaryAgent.set(agent, defensive_updates, %{
          strict_validation: true,
          boundary_enforcement: :enabled,
          audit_mode: :comprehensive
        })

      case result1 do
        {:ok, updated_agent} ->
          # Defensive update should maintain type safety
          assert updated_agent.state.status == :validating
          assert updated_agent.state.security_level == :high
          assert is_map(updated_agent.state.validated_data)

        error ->
          flunk("Defensive validation pattern failed: #{inspect(error)}")
      end

      # Now test with map opts (should work but triggers type violation)
      result2 =
        DefensiveBoundaryAgent.set(agent, defensive_updates, %{
          strict_validation: true,
          boundary_enforcement: :enabled,
          audit_mode: :comprehensive
        })

      assert {:ok, _} = result2
    end

    test "reproduces boundary enforcement with callback integration" do
      agent = DefensiveBoundaryAgent.new()

      # Set up agent state that will trigger defensive callbacks
      {:ok, prepared_agent} =
        DefensiveBoundaryAgent.set(
          agent,
          %{
            status: :ready,
            security_level: :high,
            error_count: 0
          },
          %{callback_prep: true}
        )

      # Trigger the defensive validation callback
      # This pattern from the demo exposed type issues in callback handling
      validation_result = DefensiveBoundaryAgent.on_before_validate_state(prepared_agent)

      case validation_result do
        {:ok, validated_agent} ->
          # Should have audit trail entry from defensive callback
          assert length(validated_agent.state.audit_trail) > 0

          audit_entry = hd(validated_agent.state.audit_trail)
          assert audit_entry.action == :pre_validation
          assert audit_entry.status == :ready

        error ->
          flunk("Defensive validation callback failed: #{inspect(error)}")
      end
    end
  end

  describe "Defensive Boundary Pattern #2: Production environment patterns" do
  end

  describe "Defensive Boundary Pattern #3: Error boundary enforcement" do
    test "reproduces error boundary patterns that triggered type violations" do
      agent = DefensiveBoundaryAgent.new()

      # Pattern that implements comprehensive error boundaries
      # This was one of the patterns that exposed type issues in the demo

      error_scenarios = [
        # Standard Jido errors
        %Jido.Error{
          type: :validation_error,
          message: "Invalid input",
          details: %{field: :status}
        },
        %Jido.Error{type: :execution_error, message: "Processing failed", details: %{step: 3}},

        # System errors that need defensive handling
        %RuntimeError{message: "Unexpected system error"},
        %ArgumentError{message: "Invalid argument provided"},

        # Custom error patterns
        {:error, "Custom error format"},
        "String error message",

        # Edge case errors
        %{error_type: :custom, message: "Map-based error"},
        :error_atom
      ]

      Enum.each(error_scenarios, fn error ->
        # Test defensive error handling for each scenario
        result = DefensiveBoundaryAgent.on_error(agent, error)

        case result do
          {:ok, error_handled_agent} ->
            # Should have incremented error count and updated audit trail
            assert error_handled_agent.state.error_count == 1
            assert length(error_handled_agent.state.audit_trail) > 0

            # Verify audit trail contains error information
            audit_entry = hd(error_handled_agent.state.audit_trail)
            assert audit_entry.action == :error_handling
            assert audit_entry.error == error
            assert audit_entry.error_count == 1

          failure ->
            flunk(
              "Defensive error handling failed for error #{inspect(error)}: #{inspect(failure)}"
            )
        end
      end)
    end

    test "reproduces cascading error patterns with defensive recovery" do
      agent = DefensiveBoundaryAgent.new()

      # Simulate cascading errors that trigger defensive recovery mechanisms
      # This pattern exposed complex type issues in the original demo

      errors = [
        %Jido.Error{type: :execution_error, message: "First error", details: %{}},
        %Jido.Error{type: :validation_error, message: "Second error", details: %{}},
        %Jido.Error{type: :timeout, message: "Third error", details: %{}}
      ]

      # Process errors sequentially to test cascading defensive behavior
      final_agent =
        Enum.reduce(errors, agent, fn error, current_agent ->
          case DefensiveBoundaryAgent.on_error(current_agent, error) do
            {:ok, updated_agent} -> updated_agent
            # Defensive fallback
            {:error, _reason} -> current_agent
          end
        end)

      # After multiple errors, defensive mechanisms should be active
      assert final_agent.state.error_count == 3
      assert final_agent.state.status == :error_monitoring
      assert length(final_agent.state.audit_trail) == 3

      # Test that agent is still functional but in defensive mode
      recovery_result =
        DefensiveBoundaryAgent.set(
          final_agent,
          %{
            status: :recovering,
            processing_mode: :defensive
          },
          %{recovery_mode: true}
        )

      assert {:ok, _recovering_agent} = recovery_result
    end
  end

  describe "Defensive Boundary Pattern #4: Complex integration scenarios" do
    test "reproduces full defensive workflow that exposed multiple type issues" do
      # This test reproduces the complete defensive workflow from the demo
      # that triggered multiple overlapping type violations

      agent = DefensiveBoundaryAgent.new()

      # Step 1: Initialize with defensive configuration
      {:ok, initialized_agent} =
        DefensiveBoundaryAgent.set(
          agent,
          %{
            status: :initializing,
            security_level: :high,
            processing_mode: :strict
          },
          %{defensive_mode: true}
        )

      # Step 2: Trigger defensive pre-validation
      {:ok, pre_validated_agent} =
        DefensiveBoundaryAgent.on_before_validate_state(initialized_agent)

      # Step 3: Perform defensive validation
      {:ok, validated_agent} =
        DefensiveBoundaryAgent.validate(pre_validated_agent, %{
          strict_validation: true,
          boundary_checks: :enabled
        })

      # Step 4: Update to ready state with defensive checks
      {:ok, ready_agent} =
        DefensiveBoundaryAgent.set(
          validated_agent,
          %{
            status: :validated,
            validated_data: %{
              security_check: :passed,
              boundary_validation: :complete,
              defensive_mode: :active
            }
          },
          %{workflow_complete: true}
        )

      # Add type violation test - map opts instead of keyword (should work but fails)
      result_violation =
        DefensiveBoundaryAgent.set(validated_agent, %{status: :error_test}, %{
          defensive_mode: true,
          strict_validation: true
        })

      assert {:ok, _} = result_violation

      # Step 5: Trigger defensive pre-execution
      {:ok, pre_execution_agent} = DefensiveBoundaryAgent.on_before_run(ready_agent)

      # Final verification of defensive workflow
      assert pre_execution_agent.state.status == :secure_execution
      assert pre_execution_agent.state.security_level == :high
      assert length(pre_execution_agent.state.audit_trail) > 0

      # Verify audit trail shows complete defensive workflow
      audit_actions = Enum.map(pre_execution_agent.state.audit_trail, & &1.action)
      assert :pre_validation in audit_actions

      # Additional type violation tests with map opts
      violation_result1 =
        DefensiveBoundaryAgent.set(initialized_agent, %{status: :test1}, %{mode: :violation1})

      assert {:ok, _} = violation_result1

      violation_result2 =
        DefensiveBoundaryAgent.set(pre_validated_agent, %{status: :test2}, %{mode: :violation2})

      assert {:ok, _} = violation_result2

      violation_result3 =
        DefensiveBoundaryAgent.set(ready_agent, %{status: :test3}, %{mode: :violation3})

      assert {:ok, _} = violation_result3

      # Additional violations for testing
      violation_result4 =
        DefensiveBoundaryAgent.set(validated_agent, %{status: :test4}, %{extra: :violation4})

      assert {:ok, _} = violation_result4
    end

    test "reproduces defensive boundary with external integration patterns" do
      # Test defensive patterns when integrating with external systems
      # These patterns exposed additional type issues in the demo

      agent = ProductionDefensiveAgent.new()

      # Simulate external system integration with defensive boundaries
      external_data = %{
        resource_limits: %{
          memory: 2048,
          cpu: 200,
          disk: 10_000,
          network_bandwidth: 1000
        },
        active_connections: [
          %{id: "conn_1", type: :database, status: :active},
          %{id: "conn_2", type: :cache, status: :active},
          %{id: "conn_3", type: :message_queue, status: :standby}
        ],
        performance_metrics: %{
          requests_per_second: 150,
          average_response_time: 45,
          error_rate: 0.02,
          uptime: 99.9
        },
        feature_flags: %{
          new_algorithm: true,
          experimental_caching: false,
          advanced_monitoring: true,
          beta_features: false
        }
      }

      # Apply external data with defensive validation (keyword opts - should work)
      result1 =
        ProductionDefensiveAgent.set(agent, external_data,
          external_source: true,
          validation_mode: :strict,
          boundary_enforcement: :maximum
        )

      case result1 do
        {:ok, integrated_agent} ->
          # Defensive integration should preserve type safety
          assert is_map(integrated_agent.state.resource_limits)
          assert is_list(integrated_agent.state.active_connections)
          assert is_map(integrated_agent.state.performance_metrics)
          assert is_map(integrated_agent.state.feature_flags)

          # Verify complex nested data was handled correctly
          assert integrated_agent.state.resource_limits.memory == 2048
          assert length(integrated_agent.state.active_connections) == 3

        error ->
          flunk("Defensive external integration failed: #{inspect(error)}")
      end

      # Now test with map opts (should work but triggers type violation)
      result2 =
        ProductionDefensiveAgent.set(agent, external_data, %{
          external_source: true,
          validation_mode: :strict,
          boundary_enforcement: :maximum
        })

      assert {:ok, _} = result2
    end
  end
end
