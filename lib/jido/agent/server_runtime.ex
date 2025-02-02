defmodule Jido.Agent.Server.Runtime do
  use Private
  use ExDbug, enabled: true
  @decorate_all dbug()
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
    state = %{state | current_correlation_id: signal.jido_correlation_id}

    case execute_signal(state, signal) do
      {:ok, state, result} ->
        {:ok, state, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec enqueue_and_execute(ServerState.t(), Signal.t()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def enqueue_and_execute(%ServerState{} = state, %Signal{} = signal) do
    with {:ok, state} <- ServerState.enqueue(state, signal),
         {:ok, state} <- process_signal_queue(state) do
      {:ok, state}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  private do
    @spec process_signal_queue(ServerState.t()) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp process_signal_queue(%ServerState{} = state) do
      case ServerState.dequeue(state) do
        {:error, :empty_queue} ->
          new_state = %{state | current_correlation_id: nil}
          {:ok, new_state}

        {:ok, signal, new_state} ->
          case execute_signal(new_state, signal) do
            {:ok, updated_state, _result} when updated_state.mode == :auto ->
              process_signal_queue(updated_state)

            {:ok, updated_state, _result} ->
              {:ok, updated_state}

            {:error, reason} ->
              ServerOutput.emit_err(new_state, "jido.agent.error", %{reason: reason},
                correlation_id: new_state.current_correlation_id
              )

              {:error, reason}
          end

        error ->
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
      with {:ok, signal} <- ServerCallback.handle_signal(state, signal),
           {:ok, instructions} <- route_signal(state, signal),
           {:ok, signal_instructions} <- apply_signal_to_first_instruction(signal, instructions),
           {:ok, state} <- plan_agent_instructions(state, signal_instructions),
           {:ok, state, result} <- run_agent_instructions(state),
           {:ok, state, result} <- handle_agent_final_result(state, result) do
        {:ok, state, result}
      else
        {:error, reason} ->
          ServerOutput.emit_err(state, "jido.agent.error", %{reason: reason},
            correlation_id: state.current_correlation_id
          )

          {:error, reason}
      end
    end

    @spec route_signal(ServerState.t(), Signal.t()) ::
            {:ok, [Instruction.t()]} | {:error, term()}
    defp route_signal(%ServerState{router: nil}, %Signal{}) do
      {:error, :no_router}
    end

    defp route_signal(%ServerState{} = state, %Signal{} = signal) do
      with {:ok, instructions} <- ServerRouter.route(state, signal),
           {:ok, signal_instructions} <- apply_signal_to_first_instruction(signal, instructions) do
        {:ok, signal_instructions}
      else
        {:error, reason} ->
          ServerOutput.emit_err(state, ServerSignal.route_failed(), %{reason: reason},
            correlation_id: state.current_correlation_id
          )

          {:error, reason}
      end
    end

    defp route_signal(%ServerState{}, _invalid) do
      {:error, :invalid_signal}
    end

    @spec plan_agent_instructions(ServerState.t(), [Instruction.t()]) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp plan_agent_instructions(%ServerState{agent: agent} = state, instructions) do
      case agent.__struct__.plan(agent, instructions, %{}) do
        {:ok, planned_agent} ->
          {:ok, %{state | agent: planned_agent}}

        {:error, reason} ->
          ServerOutput.emit_err(state, ServerSignal.plan_failed(), %{error: reason},
            correlation_id: state.current_correlation_id
          )

          {:error, reason}

        error ->
          ServerOutput.emit_err(state, ServerSignal.plan_failed(), %{error: error},
            correlation_id: state.current_correlation_id
          )

          {:error, error}
      end
    end

    @spec run_agent_instructions(ServerState.t(), keyword()) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp run_agent_instructions(%ServerState{} = state, opts \\ []) do
      with {:ok, running_state} <- ensure_running_state(state),
           {:ok, final_state, result} <- do_execute_all_instructions(running_state, opts) do
        {:ok, final_state, result}
      else
        {:error, reason} -> {:error, reason}
      end
    end

    # Recursively executes all instructions in the agent's queue
    @spec do_execute_all_instructions(ServerState.t(), keyword()) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp do_execute_all_instructions(%ServerState{agent: agent} = state, opts) do
      Logger.debug(
        "Executing instructions, queue length: #{:queue.len(agent.pending_instructions)}",
        ansi: [color: :yellow]
      )

      case :queue.len(agent.pending_instructions) do
        0 ->
          Logger.debug("No pending instructions", ansi: [color: :yellow])

          case state.status do
            :running ->
              Logger.debug("State is running, transitioning to idle", ansi: [color: :yellow])

              case ServerState.transition(state, :idle) do
                {:ok, idle_state} ->
                  Logger.debug("Successfully transitioned to idle", ansi: [color: :yellow])
                  {:ok, idle_state, agent.result}

                error ->
                  Logger.error("Failed to transition to idle: #{inspect(error)}")
                  error
              end

            _ ->
              Logger.debug("State is not running, returning current state",
                ansi: [color: :yellow]
              )

              {:ok, state, agent.result}
          end

        _count ->
          try do
            Logger.debug("Running agent with opts: #{inspect(opts)}", ansi: [color: :yellow])

            case agent.__struct__.run(agent, Keyword.merge([timeout: 5000], opts)) do
              {:ok, updated_agent, directives} ->
                Logger.debug("Agent run successful, got directives: #{inspect(directives)}",
                  ansi: [color: :yellow]
                )

                state = %{state | agent: updated_agent}

                case handle_cmd_result(state, updated_agent, directives) do
                  {:ok, updated_state} ->
                    Logger.debug("Command result handled successfully", ansi: [color: :yellow])
                    do_execute_all_instructions(updated_state, opts)

                  error ->
                    Logger.error("Failed to handle command result: #{inspect(error)}",
                      ansi: [color: :yellow]
                    )

                    error
                end

              {:error, reason} ->
                Logger.error("Agent run failed: #{inspect(reason)}", ansi: [color: :yellow])

                ServerOutput.emit_err(state, ServerSignal.cmd_failed(), %{error: reason},
                  correlation_id: state.current_correlation_id
                )

                {:error, reason}
            end
          rescue
            error ->
              Logger.error(
                "Agent run crashed: #{Exception.format(:error, error, __STACKTRACE__)}",
                ansi: [color: :yellow]
              )

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
      Logger.debug("Handling command result with #{length(directives)} directives")

      with {:ok, state} <- handle_agent_step_result(state, agent.result),
           {:ok, state} <- ServerDirective.handle(state, directives) do
        Logger.debug("Command result handled successfully")
        {:ok, state}
      else
        error ->
          Logger.error("Failed to handle command result: #{inspect(error)}")
          error
      end
    end

    @spec handle_agent_step_result(ServerState.t(), term()) :: {:ok, ServerState.t()}
    defp handle_agent_step_result(%ServerState{} = state, result, opts \\ []) do
      Logger.debug("Handling agent step result: #{inspect(result)}")
      opts = Keyword.put_new(opts, :correlation_id, state.current_correlation_id)
      ServerOutput.emit_out(state, result, opts)
      {:ok, state}
    end

    @spec handle_agent_final_result(ServerState.t(), term()) :: {:ok, ServerState.t(), term()}
    defp handle_agent_final_result(%ServerState{} = state, result, opts \\ []) do
      Logger.debug("Handling agent final result: #{inspect(result)}")

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
      try do
        merged_params = Map.merge(first.params || %{}, signal.data || %{})
        result = [%{first | params: merged_params} | rest]
        {:ok, result}
      rescue
        error ->
          {:error, error}
      end
    end

    defp apply_signal_to_first_instruction(%Signal{}, []), do: {:ok, []}
    defp apply_signal_to_first_instruction(%Signal{}, _), do: {:error, :invalid_instruction}

    @spec ensure_running_state(ServerState.t()) :: {:ok, ServerState.t()} | {:error, term()}
    defp ensure_running_state(%ServerState{status: :idle} = state) do
      ServerState.transition(state, :running)
    end

    defp ensure_running_state(%ServerState{status: :running} = state) do
      {:ok, state}
    end

    defp ensure_running_state(%ServerState{status: status}) do
      {:error, {:invalid_state, status}}
    end
  end
end
