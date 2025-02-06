defmodule Jido.Agent.Server.Runtime do
  use Private
  use ExDbug, enabled: false
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

  @spec handle_sync_signal(ServerState.t(), Signal.t()) ::
          {:ok, ServerState.t(), term()} | {:error, term()}
  def handle_sync_signal(%ServerState{} = state, %Signal{} = signal) do
    dbug("Executing signal", signal: signal)

    state = %{
      state
      | current_correlation_id: signal.jido_correlation_id,
        current_signal_type: :sync,
        current_signal: signal
    }

    case execute_signal(state, signal) do
      {:ok, state, result} ->
        dbug("Signal execution successful", result: result)
        {:ok, state, result}

      {:error, reason} ->
        dbug("Signal execution failed", reason: reason)
        {:error, reason}
    end
  end

  @spec handle_async_signal(ServerState.t(), Signal.t()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def handle_async_signal(%ServerState{} = state, %Signal{} = signal) do
    dbug("Enqueuing and executing signal", signal: signal)
    state = %{state | current_signal_type: :async, current_signal: signal}

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

              :execution_error
              |> ServerSignal.err_signal(
                new_state,
                Error.execution_error("Error processing signal queue", %{reason: reason})
              )
              |> ServerOutput.emit()

              {:error, reason}
          end

        error ->
          dbug("Queue processing error", error: error)

          :execution_error
          |> ServerSignal.err_signal(
            state,
            Error.execution_error("Error processing signal queue", %{reason: error})
          )
          |> ServerOutput.emit()

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
           {:ok, state, result} <- execute_agent_instructions(state, signal_instructions),
           {:ok, state, result} <- handle_agent_final_result(state, result) do
        dbug("Signal execution completed successfully", result: result)
        {:ok, state, result}
      else
        {:error, reason} ->
          dbug("Signal execution failed", reason: reason)

          :execution_error
          |> ServerSignal.err_signal(
            state,
            Error.execution_error("Error executing signal", %{reason: reason})
          )
          |> ServerOutput.emit()

          {:error, reason}
      end
    end

    @spec execute_agent_instructions(ServerState.t(), [Instruction.t()]) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp execute_agent_instructions(%ServerState{agent: agent} = state, instructions) do
      dbug("Executing agent instructions", instructions: instructions)

      # Set causation_id from first instruction if available
      causation_id =
        case instructions do
          [%Instruction{id: id} | _] when not is_nil(id) -> id
          _ -> nil
        end

      state = %{state | current_causation_id: causation_id}

      case agent.__struct__.cmd(agent, instructions, %{}) do
        {:ok, updated_agent, directives} ->
          dbug("Instructions executed successfully")
          state = %{state | agent: updated_agent}

          case handle_cmd_result(state, updated_agent, directives) do
            {:ok, final_state} ->
              # Update the agent's result in the state
              final_state = %{
                final_state
                | agent: %{final_state.agent | result: updated_agent.result}
              }

              {:ok, final_state, updated_agent.result}

            error ->
              error
          end

        {:error, reason} ->
          dbug("Instruction execution failed", reason: reason)

          :execution_error
          |> ServerSignal.err_signal(
            state,
            Error.execution_error("Error executing instructions", %{reason: reason})
          )
          |> ServerOutput.emit()

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

      case ServerRouter.route(state, signal) do
        {:ok, instructions} ->
          dbug("Signal routed successfully", instructions: instructions)
          {:ok, instructions}

        {:error, reason} ->
          dbug("Signal routing failed", reason: reason)

          :route_failed
          |> ServerSignal.err_signal(
            state,
            Error.execution_error("Error routing signal", %{reason: reason})
          )
          |> ServerOutput.emit()

          {:error, reason}
      end
    end

    defp route_signal(%ServerState{}, _invalid) do
      dbug("Invalid signal provided")
      {:error, :invalid_signal}
    end

    @spec handle_cmd_result(ServerState.t(), term(), [Directive.t()]) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp handle_cmd_result(%ServerState{} = state, agent, directives) do
      dbug("Handling command result", directive_count: length(directives))

      with {:ok, state} <- handle_agent_instruction_result(state, agent.result, []),
           {:ok, state} <- ServerDirective.handle(state, directives) do
        dbug("Command result handled successfully")
        {:ok, state}
      else
        error ->
          dbug("Failed to handle command result", error: error)
          error
      end
    end

    @spec handle_agent_instruction_result(ServerState.t(), term(), Keyword.t()) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp handle_agent_instruction_result(%ServerState{} = state, result, _opts) do
      dbug("Handling agent instruction", result: result)

      # Process the instruction result through callbacks first
      with {:ok, processed_result} <-
             ServerCallback.process_result(state, state.current_signal, result) do
        # Use the signal's dispatch config if present, otherwise use server's default
        dispatch_config =
          case state.current_signal do
            %Signal{jido_dispatch: dispatch} when not is_nil(dispatch) ->
              dbug("Using signal's dispatch config", dispatch: dispatch)
              dispatch

            _ ->
              dbug("Using server's default dispatch config")
              state.dispatch
          end

        opts = [
          correlation_id: state.current_correlation_id,
          causation_id: state.current_causation_id,
          dispatch: dispatch_config
        ]

        :instruction_result
        |> ServerSignal.out_signal(state, processed_result, opts)
        |> ServerOutput.emit(opts)

        {:ok, state}
      end
    end

    @spec handle_agent_final_result(ServerState.t(), term(), Keyword.t()) ::
            {:ok, ServerState.t(), term()}
    defp handle_agent_final_result(%ServerState{} = state, result, opts \\ []) do
      dbug("Handling agent final result", result: result)

      # Process the final result through callbacks first
      with {:ok, processed_result} <-
             ServerCallback.process_result(state, state.current_signal, result) do
        case state.current_signal_type do
          :sync ->
            dbug("Sync signal result", result: processed_result)
            {:ok, state, processed_result}

          :async ->
            # Use the signal's dispatch config if present, otherwise use server's default
            dispatch_config =
              case state.current_signal do
                %Signal{jido_dispatch: dispatch} when not is_nil(dispatch) ->
                  dbug("Using signal's dispatch config", dispatch: dispatch)
                  dispatch

                _ ->
                  dbug("Using server's default dispatch config")
                  state.dispatch
              end

            opts = [
              correlation_id: state.current_correlation_id,
              causation_id: state.current_causation_id,
              dispatch: dispatch_config
            ]

            :signal_result
            |> ServerSignal.out_signal(state, processed_result, opts)
            |> ServerOutput.emit(opts)

            {:ok, state, processed_result}
        end
      end
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
  end
end
