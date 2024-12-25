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
    debug("Processing signal", signal: signal)

    case RuntimeState.enqueue(state, signal) do
      {:ok, new_state} ->
        debug("Signal enqueued successfully", state: new_state)
        process_signal_queue(new_state)

      {:error, reason} ->
        debug("Failed to enqueue signal", reason: reason)
        {:error, reason}
    end
  end

  private do
    defp process_signal_queue(%RuntimeState{} = state) do
      debug("Starting queue processing", queue_size: :queue.len(state.pending))

      PubSub.emit(state, RuntimeSignal.queue_processing_started(), %{
        queue_size: :queue.len(state.pending)
      })

      case process_queue_signals(state) do
        {:ok, final_state} ->
          debug("Queue processing completed successfully")
          PubSub.emit(final_state, RuntimeSignal.queue_processing_completed(), %{})
          {:ok, final_state}

        {:error, reason} = error ->
          debug("Queue processing failed", reason: reason)
          # Emit failure event before returning error
          PubSub.emit(state, RuntimeSignal.queue_processing_failed(), %{reason: reason})
          error
      end
    end

    defp process_queue_signals(%RuntimeState{} = state) do
      debug("Processing next signal in queue")

      case RuntimeState.dequeue(state) do
        {:ok, signal, new_state} ->
          debug("Dequeued signal", signal: signal)

          case execute_signal(new_state, signal) do
            {:ok, updated_state} ->
              debug("Signal executed successfully")
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

            {:error, reason} = error ->
              debug("Signal execution failed", reason: reason)
              error
          end

        {:error, :empty_queue} ->
          debug("Queue empty, processing complete")
          {:ok, state}
      end
    end

    defp execute_signal(%RuntimeState{} = state, %Signal{} = signal) do
      debug("Executing signal", signal: signal, state_status: state.status)

      try do
        cond do
          RuntimeSignal.is_agent_signal?(signal) ->
            debug("Executing agent signal", signal: signal)
            execute_agent_signal(state, signal)

          RuntimeSignal.is_syscall_signal?(signal) ->
            debug("Executing syscall signal", signal: signal)
            execute_syscall_signal(state, signal)

          true ->
            debug("Unknown signal type", type: signal.type)
            {:ignore, {:unknown_signal_type, signal.type}}
        end
      rescue
        error ->
          debug("Signal execution failed with error", error: error)
          {:error, {:signal_execution_failed, error}}
      end
    end

    defp execute_syscall_signal(%RuntimeState{} = state, %Signal{} = signal) do
      debug("Processing syscall signal", signal: signal)

      cond do
        RuntimeSignal.is_process_start?(signal) ->
          debug("Executing process start syscall", child_spec: signal.data.child_spec)

          case Syscall.execute(state, {:spawn, signal.data.child_spec}) do
            {{:ok, pid}, new_state} ->
              debug("Process started successfully", pid: pid)
              {:ok, new_state}

            {error, _state} ->
              debug("Process start failed", error: error)
              error
          end

        RuntimeSignal.is_process_terminate?(signal) ->
          debug("Executing process terminate syscall", child_pid: signal.data.child_pid)

          case Syscall.execute(state, {:kill, signal.data.child_pid}) do
            {:ok, new_state} ->
              debug("Process terminated successfully")
              {:ok, new_state}

            {{:error, reason}, _state} ->
              debug("Process termination failed", reason: reason)
              {:error, reason}
          end

        true ->
          debug("Unknown runtime signal", type: signal.type)
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
      debug("Executing agent signal in #{status} state", signal: signal)

      with {:ok, running_state} <- ensure_running_state(state),
           {:ok, result} <- agent_signal_cmd(running_state, signal),
           {:ok, runtime_with_agent} <- handle_action_result(running_state, result),
           {:ok, idle_state} <- RuntimeState.transition(runtime_with_agent, :idle) do
        debug("Agent signal executed successfully")
        {:ok, idle_state}
      end
    end

    defp execute_agent_signal(%RuntimeState{status: status}, _signal) do
      debug("Invalid state for agent signal execution", status: status)
      {:error, {:invalid_state, status}}
    end

    # Execute action and handle syscalls
    defp agent_signal_cmd(%RuntimeState{status: :running} = state, %Signal{} = signal) do
      {action, params, opts} = RuntimeSignal.signal_to_action(signal)
      debug("Executing agent command", action: action, params: params, opts: opts)

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
      debug("Invalid state for agent command", status: status)
      {:error, {:invalid_state, status}}
    end

    defp handle_action_result(%RuntimeState{} = state, %{result: {:syscall, syscall}} = result) do
      debug("Handling syscall result", syscall: syscall)

      case Syscall.execute(state, syscall) do
        {:ok, new_state} ->
          debug("Syscall executed successfully")
          {:ok, %{result | result: new_state}}

        error ->
          debug("Syscall execution failed", error: error)
          error
      end
    end

    defp handle_action_result(%RuntimeState{} = runtime_state, %{result: agent_state} = _result)
         when is_struct(agent_state) do
      debug("Updating runtime state with new agent state")
      PubSub.emit(runtime_state, "result", %{agent_state: agent_state})
      {:ok, %{runtime_state | agent: agent_state}}
    end

    defp handle_action_result(%RuntimeState{} = state, result) do
      debug("No state update needed")
      PubSub.emit(state, "result", %{result: result})
      {:ok, state}
    end

    defp ensure_running_state(%RuntimeState{status: :idle} = state) do
      debug("Transitioning from idle to running state")

      with {:ok, running_state} <- RuntimeState.transition(state, :running) do
        {:ok, running_state}
      end
    end

    defp ensure_running_state(%RuntimeState{status: :running} = state) do
      debug("State already running")
      {:ok, state}
    end

    defp ensure_running_state(%RuntimeState{status: status}) do
      debug("Cannot transition to running state", current_status: status)
      {:error, {:invalid_state, status}}
    end
  end
end
