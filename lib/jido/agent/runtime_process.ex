defmodule Jido.Agent.Runtime.Process do
  @moduledoc """
  Helper module for managing child processes under the Runtime's DynamicSupervisor.
  """

  use Jido.Util, debug_enabled: false
  alias Jido.Agent.Runtime.State, as: RuntimeState
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  alias Jido.Agent.Runtime.PubSub

  @doc """
  Starts a child process under the Runtime's DynamicSupervisor.

  Returns {:ok, pid} if successful, {:error, reason} on failure.
  """
  @spec start(%RuntimeState{}, map()) :: {:ok, pid()} | {:error, term()}
  def start(%RuntimeState{child_supervisor: supervisor} = state, child_spec)
      when is_pid(supervisor) do
    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} = result ->
        debug("Started child process",
          agent_id: state.agent.id,
          child_pid: inspect(pid),
          child_spec: inspect(child_spec)
        )

        PubSub.emit(state, RuntimeSignal.process_started(), %{
          child_pid: pid,
          child_spec: child_spec
        })

        result

      {:error, reason} = error ->
        debug("Failed to start child process",
          agent_id: state.agent.id,
          reason: inspect(reason),
          child_spec: inspect(child_spec)
        )

        PubSub.emit(state, RuntimeSignal.process_start_failed(), %{
          reason: reason,
          child_spec: child_spec
        })

        error
    end
  end

  @doc """
  Lists all child processes currently running under the Runtime's DynamicSupervisor.

  Returns list of child specifications.
  """
  @spec list(%RuntimeState{}) :: [{:undefined, pid(), :worker, [module()]}]
  def list(%RuntimeState{child_supervisor: supervisor}) when is_pid(supervisor) do
    DynamicSupervisor.which_children(supervisor)
  end

  @doc """
  Terminates a specific child process under the Runtime's DynamicSupervisor.

  Returns :ok if successful, {:error, reason} on failure.
  """
  @spec terminate(%RuntimeState{}, pid()) :: :ok | {:error, :not_found}
  def terminate(%RuntimeState{child_supervisor: supervisor} = state, child_pid)
      when is_pid(supervisor) do
    case DynamicSupervisor.terminate_child(supervisor, child_pid) do
      :ok ->
        debug("Terminated child process",
          agent_id: state.agent.id,
          child_pid: inspect(child_pid)
        )

        PubSub.emit(state, RuntimeSignal.process_terminated(), %{
          child_pid: child_pid
        })

        :ok

      {:error, reason} = error ->
        debug("Failed to terminate child process",
          agent_id: state.agent.id,
          child_pid: inspect(child_pid),
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Restarts a specific child process under the Runtime's DynamicSupervisor.

  This is done by terminating the existing process and starting a new one with the same spec.

  Returns {:ok, new_pid} if successful, {:error, reason} on failure.
  """
  @spec restart(%RuntimeState{}, pid(), map()) :: {:ok, pid()} | {:error, term()}
  def restart(%RuntimeState{} = state, child_pid, child_spec) do
    with :ok <- terminate(state, child_pid),
         {:ok, new_pid} = result <- start(state, child_spec) do
      debug("Restarted child process",
        agent_id: state.agent.id,
        old_pid: inspect(child_pid),
        new_pid: inspect(new_pid)
      )

      PubSub.emit(state, RuntimeSignal.process_restart_succeeded(), %{
        old_pid: child_pid,
        new_pid: new_pid,
        child_spec: child_spec
      })

      result
    else
      error ->
        PubSub.emit(state, RuntimeSignal.process_restart_failed(), %{
          child_pid: child_pid,
          child_spec: child_spec,
          error: error
        })

        error
    end
  end
end
