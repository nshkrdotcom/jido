defmodule Jido.Agent.Server.Runtime do
  use Private
  use ExDbug, enabled: true
  require Logger

  alias Jido.Error
  alias Jido.Signal
  alias Jido.Instruction
  alias Jido.Agent.Server.Callback, as: ServerCallback
  alias Jido.Agent.Server.Router, as: ServerRouter
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.Output, as: ServerOutput
  alias Jido.Agent.Server.Directive, as: ServerDirective

  @spec execute(ServerState.t(), Signal.t()) ::
          {:ok, ServerState.t(), term()} | {:error, term()}
  def execute(%ServerState{} = state, %Signal{} = signal) do
    dbug("Executing signal", signal: signal)
    state = %{state | current_correlation_id: signal.jido_correlation_id}

    case execute_signal(state, signal) do
      {:ok, state, result} ->
        dbug("Signal execution successful", result: result)
        {:ok, state, result}

      {:error, reason} ->
        dbug("Signal execution failed", reason: reason)
        {:error, reason}
    end
  end

  @spec enqueue_and_execute(ServerState.t(), Signal.t()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def enqueue_and_execute(%ServerState{} = state, %Signal{} = signal) do
    dbug("Enqueuing and executing signal", signal: signal)

    with {:ok, state} <- ServerState.enqueue(state, signal),
         {:ok, state} <- process_signal_queue(state) do
      dbug("Signal enqueued and executed successfully")
      {:ok, state}
    else
      {:error, reason} ->
        dbug("Failed to enqueue/execute signal", reason: reason)
        {:error, reason}
    end
  end

  private do
    @spec process_signal_queue(ServerState.t()) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp process_signal_queue(%ServerState{} = state) do
      dbug("Processing signal queue")

      case ServerState.dequeue(state) do
        {:error, :empty_queue} ->
          dbug("Queue empty, resetting correlation ID")
          new_state = %{state | current_correlation_id: nil}
          {:ok, new_state}

        {:ok, signal, new_state} ->
          dbug("Dequeued signal", signal: signal)

          case execute_signal(new_state, signal) do
            {:ok, updated_state, result} when updated_state.mode == :auto ->
              dbug("Auto mode, continuing queue processing", result: result)
              process_signal_queue(updated_state)

            {:ok, updated_state, result} ->
              dbug("Manual mode, stopping queue processing", result: result)
              {:ok, updated_state}

            {:error, reason} ->
              dbug("Signal execution failed", reason: reason)

              ServerOutput.emit_err(new_state, "jido.agent.error", %{reason: reason},
                correlation_id: new_state.current_correlation_id
              )

              {:error, reason}
          end

        error ->
          dbug("Queue processing error", error: error)

          ServerOutput.emit_err(
            state,
            "jido.agent.error",
            Error.execution_error("Error processing signal queue", %{reason: error})
          )

          {:error, error}
      end
    end

    @spec execute_signal(ServerState.t(), Signal.t()) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp execute_signal(%ServerState{} = state, %Signal{} = signal) do
      dbug("Executing signal", signal: signal)

      with {:ok, signal} <- ServerCallback.handle_signal(state, signal),
           {:ok, instructions} <- route_signal(state, signal),
           {:ok, signal_instructions} <- apply_signal_to_first_instruction(signal, instructions),
           {:ok, state} <- plan_agent_instructions(state, signal_instructions),
           {:ok, state, result} <- run_agent_instructions(state),
           {:ok, state, result} <- handle_agent_final_result(state, result) do
        dbug("Signal execution completed successfully", result: result)
        {:ok, state, result}
      else
        {:error, reason} ->
          dbug("Signal execution failed", reason: reason)

          ServerOutput.emit_err(state, "jido.agent.error", %{reason: reason},
            correlation_id: state.current_correlation_id
          )

          {:error, reason}
      end
    end

    @spec route_signal(ServerState.t(), Signal.t()) ::
            {:ok, [Instruction.t()]} | {:error, term()}
    defp route_signal(%ServerState{router: nil}, %Signal{}) do
      dbug("No router configured")
      {:error, :no_router}
    end

    defp route_signal(%ServerState{} = state, %Signal{} = signal) do
      dbug("Routing signal", signal: signal)

      with {:ok, instructions} <- ServerRouter.route(state, signal),
           {:ok, signal_instructions} <- apply_signal_to_first_instruction(signal, instructions) do
        dbug("Signal routed successfully", instructions: signal_instructions)
        {:ok, signal_instructions}
      else
        {:error, reason} ->
          dbug("Signal routing failed", reason: reason)

          ServerOutput.emit_err(state, ServerSignal.route_failed(), %{reason: reason},
            correlation_id: state.current_correlation_id
          )

          {:error, reason}
      end
    end

    defp route_signal(%ServerState{}, _invalid) do
      dbug("Invalid signal provided")
      {:error, :invalid_signal}
    end

    @spec plan_agent_instructions(ServerState.t(), [Instruction.t()]) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp plan_agent_instructions(%ServerState{agent: agent} = state, instructions) do
      dbug("Planning agent instructions", instructions: instructions)

      case agent.__struct__.plan(agent, instructions, %{}) do
        {:ok, planned_agent} ->
          dbug("Instructions planned successfully")
          {:ok, %{state | agent: planned_agent}}

        {:error, reason} ->
          dbug("Instruction planning failed", reason: reason)

          ServerOutput.emit_err(state, ServerSignal.plan_failed(), %{error: reason},
            correlation_id: state.current_correlation_id
          )

          {:error, reason}

        error ->
          dbug("Unexpected planning error", error: error)

          ServerOutput.emit_err(state, ServerSignal.plan_failed(), %{error: error},
            correlation_id: state.current_correlation_id
          )

          {:error, error}
      end
    end

    @spec run_agent_instructions(ServerState.t(), keyword()) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp run_agent_instructions(%ServerState{} = state, opts \\ []) do
      dbug("Running agent instructions", opts: opts)

      with {:ok, running_state} <- ensure_running_state(state),
           {:ok, final_state, result} <- do_execute_all_instructions(running_state, opts) do
        dbug("Instructions executed successfully", result: result)
        {:ok, final_state, result}
      else
        {:error, reason} ->
          dbug("Instruction execution failed", reason: reason)
          {:error, reason}
      end
    end

    # Recursively executes all instructions in the agent's queue
    @spec do_execute_all_instructions(ServerState.t(), keyword()) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp do_execute_all_instructions(%ServerState{agent: agent} = state, opts) do
      queue_length = :queue.len(agent.pending_instructions)
      dbug("Executing instructions", queue_length: queue_length)

      case queue_length do
        0 ->
          dbug("No pending instructions")

          case state.status do
            :running ->
              dbug("State is running, transitioning to idle")

              case ServerState.transition(state, :idle) do
                {:ok, idle_state} ->
                  dbug("Successfully transitioned to idle")
                  {:ok, idle_state, agent.result}

                error ->
                  dbug("Failed to transition to idle", error: error)
                  error
              end

            _ ->
              dbug("State is not running, returning current state")
              {:ok, state, agent.result}
          end

        _count ->
          try do
            dbug("Running agent", opts: opts)

            case agent.__struct__.run(agent, Keyword.merge([timeout: 5000], opts)) do
              {:ok, updated_agent, directives} ->
                dbug("Agent run successful", directives: directives)

                state = %{state | agent: updated_agent}

                case handle_cmd_result(state, updated_agent, directives) do
                  {:ok, updated_state} ->
                    dbug("Command result handled successfully")
                    do_execute_all_instructions(updated_state, opts)

                  error ->
                    dbug("Failed to handle command result", error: error)
                    error
                end

              {:error, reason} ->
                dbug("Agent run failed", reason: reason)

                ServerOutput.emit_err(state, ServerSignal.cmd_failed(), %{error: reason},
                  correlation_id: state.current_correlation_id
                )

                {:error, reason}
            end
          rescue
            error ->
              dbug("Agent run crashed", error: error, stacktrace: __STACKTRACE__)

              ServerOutput.emit_err(state, ServerSignal.cmd_failed(), %{error: error},
                correlation_id: state.current_correlation_id
              )

              {:error, error}
          end
      end
    end

    @spec handle_cmd_result(ServerState.t(), term(), [Directive.t()]) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp handle_cmd_result(%ServerState{} = state, agent, directives) do
      dbug("Handling command result", directive_count: length(directives))

      with {:ok, state} <- handle_agent_step_result(state, agent.result),
           {:ok, state} <- ServerDirective.handle(state, directives) do
        dbug("Command result handled successfully")
        {:ok, state}
      else
        error ->
          dbug("Failed to handle command result", error: error)
          error
      end
    end

    @spec handle_agent_step_result(ServerState.t(), term()) :: {:ok, ServerState.t()}
    defp handle_agent_step_result(%ServerState{} = state, result, opts \\ []) do
      dbug("Handling agent step result", result: result)
      opts = Keyword.put_new(opts, :correlation_id, state.current_correlation_id)
      ServerOutput.emit_out(state, result, opts)
      {:ok, state}
    end

    @spec handle_agent_final_result(ServerState.t(), term()) :: {:ok, ServerState.t(), term()}
    defp handle_agent_final_result(%ServerState{} = state, result, opts \\ []) do
      dbug("Handling agent final result", result: result)

      opts =
        Keyword.merge(opts,
          correlation_id: state.current_correlation_id,
          causation_id: state.current_causation_id
        )

      ServerOutput.emit_out(state, result, opts)
      {:ok, state, result}
    end

    @spec apply_signal_to_first_instruction(Signal.t(), [Instruction.t()]) ::
            {:ok, [Instruction.t()]} | {:error, term()}
    defp apply_signal_to_first_instruction(%Signal{} = signal, [%Instruction{} = first | rest]) do
      dbug("Applying signal to first instruction", instruction: first)

      try do
        merged_params = Map.merge(first.params || %{}, signal.data || %{})
        result = [%{first | params: merged_params} | rest]
        dbug("Signal applied successfully")
        {:ok, result}
      rescue
        error ->
          dbug("Failed to apply signal", error: error)
          {:error, error}
      end
    end

    defp apply_signal_to_first_instruction(%Signal{}, []) do
      dbug("No instructions to apply signal to")
      {:ok, []}
    end

    defp apply_signal_to_first_instruction(%Signal{}, _) do
      dbug("Invalid instruction format")
      {:error, :invalid_instruction}
    end

    @spec ensure_running_state(ServerState.t()) :: {:ok, ServerState.t()} | {:error, term()}
    defp ensure_running_state(%ServerState{status: :idle} = state) do
      dbug("Transitioning from idle to running state")
      ServerState.transition(state, :running)
    end

    defp ensure_running_state(%ServerState{status: :running} = state) do
      dbug("State already running")
      {:ok, state}
    end

    defp ensure_running_state(%ServerState{status: status}) do
      dbug("Invalid state for running", status: status)
      {:error, {:invalid_state, status}}
    end
  end
end
