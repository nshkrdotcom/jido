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

  @spec handle_sync_signal(ServerState.t(), Signal.t()) ::
          {:ok, ServerState.t(), term()} | {:error, term()}
  def handle_sync_signal(%ServerState{} = state, %Signal{} = signal) do
    with {:ok, state} <- set_correlation_id(state, signal),
         state <- set_current_signal(state, signal),
         state <- set_signal_type(state, :sync),
         {:ok, state, result} <- execute_signal(state, signal) do
      {:ok, state, result}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec handle_async_signal(ServerState.t(), Signal.t()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def handle_async_signal(%ServerState{} = state, %Signal{} = signal) do
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
      with {:ok, signal, state} <- ServerState.dequeue(state),
           {:ok, state} <- set_correlation_id(state, signal),
           state <- set_current_signal(state, signal),
           state <- set_signal_type(state, :async),
           {:ok, state, _result} <- execute_signal(state, signal) do
        # Continue processing the queue
        process_signal_queue(state)
      else
        {:error, :empty_queue} ->
          # When queue is empty, return idle state
          state =
            state
            |> clear_runtime_state()
            |> ensure_state(:idle)

          {:ok, state}

        {:error, reason} ->
          runtime_error(state, "Error processing signal queue", reason)
          {:error, reason}

        error ->
          runtime_error(state, "Error processing signal queue", error)
          {:error, error}
      end
    end

    @spec execute_signal(ServerState.t(), Signal.t()) ::
            {:ok, ServerState.t(), term()} | {:error, term()}
    defp execute_signal(%ServerState{} = state, %Signal{} = signal) do
      with {:ok, signal} <- ServerCallback.handle_signal(state, signal),
           {:ok, instructions} <- route_signal(state, signal),
           {:ok, instructions} <- apply_signal_to_first_instruction(signal, instructions),
           {:ok, opts} <- extract_opts_from_first_instruction(instructions),
           {:ok, state, result} <- do_agent_cmd(state, instructions, opts),
           {:ok, state, result} <- handle_signal_result(state, signal, result) do
        {:ok, state, result}
      else
        {:error, reason} ->
          runtime_error(state, "Error executing signal", reason)
          {:error, reason}
      end
    end

    defp execute_signal(%ServerState{} = state, _invalid_signal) do
      runtime_error(state, "Invalid signal format", :invalid_signal)
      {:error, :invalid_signal}
    end

    defp do_agent_cmd(%ServerState{agent: agent} = state, instructions, opts) do
      case agent.__struct__.cmd(agent, instructions, opts) do
        {:ok, agent, directives} ->
          state = %{state | agent: agent}

          case handle_agent_result(state, agent, directives) do
            {:ok, state} -> do_agent_run(state, opts)
            error -> error
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp do_agent_run(%ServerState{agent: agent} = state, opts) do
      is_empty =
        case agent.pending_instructions do
          [] -> true
          queue when is_tuple(queue) -> :queue.is_empty(queue)
          _ -> false
        end

      case is_empty do
        true ->
          {:ok, state, agent.result}

        false ->
          case agent.__struct__.run(agent, opts) do
            {:ok, agent, directives} ->
              state = %{state | agent: agent}

              case handle_agent_result(state, agent, directives) do
                {:ok, state} ->
                  do_agent_run(state, opts)

                error ->
                  error
              end

            {:error, reason} ->
              {:error, reason}
          end
      end
    end

    @spec handle_agent_result(ServerState.t(), term(), [Directive.t()]) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp handle_agent_result(%ServerState{} = state, agent, directives) do
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

        # Emit instruction result signal first
        opts = [
          correlation_id: state.current_correlation_id,
          causation_id: state.current_causation_id,
          dispatch: dispatch_config
        ]

        :instruction_result
        |> ServerSignal.out_signal(state, processed_result, opts)
        |> ServerOutput.emit(opts)

        # Now handle any state transitions without emitting signals
        case state.status do
          :running ->
            # Directly update the state without emitting a signal
            new_state = %{state | status: :idle}
            {:ok, new_state}

          _ ->
            {:ok, state}
        end
      end
    end

    @spec handle_signal_result(ServerState.t(), Signal.t(), term()) ::
            {:ok, ServerState.t(), term()}
    defp handle_signal_result(%ServerState{} = state, signal, result) do
      # Process the final result through callbacks first
      with {:ok, result} <-
             ServerCallback.process_result(state, state.current_signal, result) do
        case state.current_signal_type do
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
            |> ServerSignal.out_signal(state, result, opts)
            |> ServerOutput.emit(opts)

            {:ok, state, result}

          _ ->
            # If no signal type is set, just return the result
            dbug("No signal type set, returning result as is")
            {:ok, state, result}
        end
      end
    end

    defp extract_opts_from_first_instruction(instructions) do
      case instructions do
        [%Instruction{opts: opts} | _] when not is_nil(opts) -> {:ok, opts}
        [%Instruction{} | _] -> {:ok, []}
        _ -> {:ok, []}
      end
    end

    defp route_signal(%ServerState{router: nil}, %Signal{}), do: {:error, :no_router}

    defp route_signal(%ServerState{} = state, %Signal{} = signal) do
      case ServerRouter.route(state, signal) do
        {:ok, instructions} ->
          {:ok, instructions}

        {:error, reason} ->
          runtime_error(state, "Error routing signal", reason)
          {:error, reason}
      end
    end

    defp route_signal(%ServerState{}, _invalid), do: {:error, :invalid_signal}

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

    defp runtime_error(state, message, reason) do
      :execution_error
      |> ServerSignal.err_signal(
        state,
        Error.execution_error(message, %{reason: reason})
      )
      |> ServerOutput.emit()
    end

    defp set_correlation_id(%ServerState{} = state, {:ok, %Signal{} = signal}),
      do: set_correlation_id(state, signal)

    defp set_correlation_id(%ServerState{} = state, %Signal{} = signal) do
      {:ok,
       %{
         state
         | current_correlation_id: signal.jido_correlation_id,
           current_causation_id: signal.jido_causation_id
       }}
    end

    defp set_correlation_id(%ServerState{} = state, _), do: state

    defp set_causation_id(%ServerState{} = state, instructions) when is_list(instructions) do
      causation_id =
        case instructions do
          [%Instruction{id: id} | _] when not is_nil(id) -> id
          _ -> nil
        end

      {:ok, %{state | current_causation_id: causation_id}}
    end

    defp set_causation_id(%ServerState{} = state, {:ok, %Instruction{} = instruction}),
      do: set_causation_id(state, instruction)

    defp set_causation_id(%ServerState{} = state, %Instruction{} = instruction) do
      {:ok, %{state | current_causation_id: instruction.id}}
    end

    defp set_causation_id(%ServerState{} = state, _), do: {:ok, state}

    defp clear_runtime_state(%ServerState{} = state) do
      %{
        state
        | current_correlation_id: nil,
          current_causation_id: nil,
          current_signal_type: nil,
          current_signal: nil
      }
    end

    defp set_current_signal(%ServerState{} = state, %Signal{} = signal) do
      %{state | current_signal: signal}
    end

    defp set_signal_type(%ServerState{} = state, type) when is_atom(type) do
      %{state | current_signal_type: type}
    end

    defp ensure_state(%ServerState{status: status} = state, target_status)
         when status == target_status,
         do: state

    defp ensure_state(%ServerState{status: status} = state, target_status) do
      case ServerState.transition(state, target_status) do
        {:ok, new_state} -> new_state
        {:error, _reason} -> state
      end
    end
  end
end
