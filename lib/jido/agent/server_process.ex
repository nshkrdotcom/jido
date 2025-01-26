defmodule Jido.Agent.Server.Process do
  @moduledoc false
  # Helper module for managing child processes under the Server's DynamicSupervisor.

  use ExDbug, enabled: false
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal

  @doc """
  Starts a child process under the Server's DynamicSupervisor.

  Returns {:ok, pid} if successful, {:error, reason} on failure.
  """
  @spec start(%ServerState{}, map()) :: {:ok, pid()} | {:error, term()}
  def start(%ServerState{child_supervisor: supervisor} = state, child_spec)
      when is_pid(supervisor) do
    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} = result ->
        dbug("Started child process",
          agent_id: state.agent.id,
          child_pid: inspect(pid),
          child_spec: inspect(child_spec)
        )

        ServerSignal.emit_event(state, ServerSignal.process_started(), %{
          child_pid: pid,
          child_spec: child_spec
        })

        result

      {:error, reason} = error ->
        dbug("Failed to start child process",
          agent_id: state.agent.id,
          reason: inspect(reason),
          child_spec: inspect(child_spec)
        )

        ServerSignal.emit_event(state, ServerSignal.process_failed(), %{
          reason: reason,
          child_spec: child_spec
        })

        error
    end
  end

  @doc """
  Lists all child processes currently running under the Server's DynamicSupervisor.

  Returns list of child specifications.
  """
  @spec list(%ServerState{}) :: [{:undefined, pid(), :worker, [module()]}]
  def list(%ServerState{child_supervisor: supervisor}) when is_pid(supervisor) do
    DynamicSupervisor.which_children(supervisor)
  end

  @doc """
  Terminates a specific child process under the Server's DynamicSupervisor.

  Returns :ok if successful, {:error, reason} on failure.
  """
  @spec terminate(%ServerState{}, pid()) :: :ok | {:error, :not_found}
  def terminate(%ServerState{child_supervisor: supervisor} = state, child_pid)
      when is_pid(supervisor) do
    case DynamicSupervisor.terminate_child(supervisor, child_pid) do
      :ok ->
        dbug("Terminated child process",
          agent_id: state.agent.id,
          child_pid: inspect(child_pid)
        )

        ServerSignal.emit_event(state, ServerSignal.process_terminated(), %{
          child_pid: child_pid
        })

        :ok

      {:error, _reason} = error ->
        dbug("Failed to terminate child process",
          agent_id: state.agent.id,
          child_pid: inspect(child_pid),
          reason: inspect(error)
        )

        error
    end
  end

  @doc """
  Restarts a specific child process under the Server's DynamicSupervisor.

  This is done by terminating the existing process and starting a new one with the same spec.

  Returns {:ok, new_pid} if successful, {:error, reason} on failure.
  """
  @spec restart(%ServerState{}, pid(), map()) :: {:ok, pid()} | {:error, term()}
  def restart(%ServerState{} = state, child_pid, child_spec) do
    with :ok <- terminate(state, child_pid),
         {:ok, _new_pid} = result <- start(state, child_spec) do
      dbug("Restarted child process",
        agent_id: state.agent.id,
        old_pid: inspect(child_pid),
        new_pid: inspect(result)
      )

      result
    else
      error ->
        ServerSignal.emit_event(state, ServerSignal.process_failed(), %{
          child_pid: child_pid,
          child_spec: child_spec,
          error: error
        })

        error
    end
  end
end
