defmodule Jido.Agent.Runtime.Execute do
  use Private
  use Jido.Util, debug_enabled: true

  alias Jido.Agent.Runtime.State, as: RuntimeState
  alias Jido.Agent.Runtime.{PubSub, Syscall}
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  alias Jido.Signal

  @doc """
  Processes a signal by enqueuing it and starting queue processing.
  """
  def process_signal(%RuntimeState{} = state, %Signal{} = signal) do
    case RuntimeState.enqueue(state, signal) do
      {:ok, new_state} -> process_signal_queue(new_state)
      {:error, reason} -> {:error, reason}
    end
  end

  private do
    @doc """
    Recursively processes signals in the queue until empty.
    """
    defp process_signal_queue(%RuntimeState{} = state) do
      PubSub.emit(state, RuntimeSignal.queue_processing_started(), %{
        queue_size: :queue.len(state.pending)
      })

      case process_queue_signals(state) do
        {:ok, final_state} ->
          PubSub.emit(final_state, RuntimeSignal.queue_processing_completed(), %{})
          {:ok, final_state}

        {:error, reason} = error ->
          # Emit failure event before returning error
          PubSub.emit(state, RuntimeSignal.queue_processing_failed(), %{reason: reason})
          error
      end
    end

    defp process_queue_signals(%RuntimeState{} = state) do
      case RuntimeState.dequeue(state) do
        {:ok, signal, new_state} ->
          case execute_signal(new_state, signal) do
            {:ok, updated_state} ->
              PubSub.emit(updated_state, RuntimeSignal.queue_step_completed(), %{signal: signal})
              process_queue_signals(updated_state)

            {:ignore, reason} ->
              debug("Ignoring signal", signal: signal, reason: reason)

              PubSub.emit(new_state, RuntimeSignal.queue_step_ignored(), %{
                signal: signal,
                ignored: true,
                reason: reason
              })

              process_queue_signals(new_state)

            {:error, _reason} = error ->
              error
          end

        {:error, :empty_queue} ->
          {:ok, state}
      end
    end

    defp execute_signal(%RuntimeState{} = state, %Signal{} = signal) do
      try do
        cond do
          RuntimeSignal.is_agent_signal?(signal) ->
            debug("Executing agent signal", signal: signal)
            execute_agent_signal(state, signal)

          RuntimeSignal.is_syscall_signal?(signal) ->
            debug("Executing syscall signal", signal: signal)
            execute_syscall_signal(state, signal)

          true ->
            {:ignore, {:unknown_signal_type, signal.type}}
        end
      rescue
        error ->
          {:error, {:signal_execution_failed, error}}
      end
    end

    defp execute_syscall_signal(%RuntimeState{} = state, %Signal{} = signal) do
      cond do
        RuntimeSignal.is_process_start?(signal) ->
          case Syscall.execute(state, {:spawn, signal.data.child_spec}) do
            {{:ok, _pid}, new_state} -> {:ok, new_state}
            {error, _state} -> error
          end

        RuntimeSignal.is_process_terminate?(signal) ->
          case Syscall.execute(state, {:kill, signal.data.child_pid}) do
            {:ok, new_state} -> {:ok, new_state}
            {{:error, reason}, _state} -> {:error, reason}
          end

        true ->
          {:ignore, {:unknown_runtime_signal, signal.type}}
      end
    end

    # Handle agent actions with state transitions
    defp execute_agent_signal(%RuntimeState{status: :paused} = state, signal) do
      debug("Agent paused, queueing signal", signal: signal)
      RuntimeState.enqueue(state, signal)
    end

    defp execute_agent_signal(%RuntimeState{status: status} = state, %Signal{} = signal)
         when status in [:idle, :running] do
      with {:ok, running_state} <- ensure_running_state(state),
           {:ok, result} <- agent_signal_cmd(running_state, signal),
           {:ok, runtime_with_agent} <- handle_action_result(running_state, result),
           {:ok, idle_state} <- RuntimeState.transition(runtime_with_agent, :idle) do
        {:ok, idle_state}
      end
    end

    defp execute_agent_signal(%RuntimeState{status: status}, _signal) do
      {:error, {:invalid_state, status}}
    end

    # Execute action and handle syscalls
    defp agent_signal_cmd(%RuntimeState{status: :running} = state, %Signal{} = signal) do
      {action, params, opts} = RuntimeSignal.signal_to_action(signal)

      try do
        state.agent.__struct__.cmd(state.agent, action, params, opts)
      rescue
        error ->
          debug("Action execution failed",
            action: action,
            error: Exception.format(:error, error, __STACKTRACE__)
          )

          :ok =
            PubSub.emit(state, RuntimeSignal.agent_cmd_failed(), %{
              signal: signal,
              reason: error
            })

          {:error, error}
      end
    end

    defp agent_signal_cmd(%RuntimeState{status: status}, %Signal{}) do
      {:error, {:invalid_state, status}}
    end

    defp handle_action_result(%RuntimeState{} = state, %{result: {:syscall, syscall}} = result) do
      case Syscall.execute(state, syscall) do
        {:ok, new_state} -> {:ok, %{result | result: new_state}}
        error -> error
      end
    end

    defp handle_action_result(%RuntimeState{} = runtime_state, %{result: agent_state} = _result)
         when is_struct(agent_state) do
      {:ok, %{runtime_state | agent: agent_state}}
    end

    defp handle_action_result(%RuntimeState{} = state, _result), do: {:ok, state}

    defp ensure_running_state(%RuntimeState{status: :idle} = state) do
      with {:ok, running_state} <- RuntimeState.transition(state, :running) do
        {:ok, running_state}
      end
    end

    defp ensure_running_state(%RuntimeState{status: :running} = state), do: {:ok, state}

    defp ensure_running_state(%RuntimeState{status: status}),
      do: {:error, {:invalid_state, status}}
  end
end
