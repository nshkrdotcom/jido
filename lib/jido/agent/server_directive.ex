defmodule Jido.Agent.Server.Directive do
  @moduledoc false
  # Executes validated directives within an agent server context.

  # This module handles applying directive structs to modify server state and behavior.
  # Only directives defined in Jido.Agent.Directive are valid.

  alias Jido.Agent.Server.Process, as: ServerProcess
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Instruction

  alias Jido.Agent.Directive.{
    Spawn,
    Kill,
    Enqueue,
    RegisterAction,
    DeregisterAction
  }

  alias Jido.{Agent.Directive, Error}
  use ExDbug, enabled: false

  @doc """
  Executes a validated directive within a server context.

  Returns a tuple containing the result and updated server state.
  """
  @spec execute(ServerState.t(), Directive.t()) :: {:ok, ServerState.t()} | {:error, Error.t()}

  def execute(%ServerState{} = _state, %Enqueue{action: nil}) do
    {:error, Error.validation_error("Invalid action", %{action: nil})}
  end

  def execute(%ServerState{} = state, %Enqueue{} = directive) do
    instruction = %Instruction{
      action: directive.action,
      params: directive.params,
      context: directive.context,
      opts: directive.opts
    }

    new_queue = :queue.in(instruction, state.pending_signals)
    {:ok, %{state | pending_signals: new_queue}}
  end

  def execute(%ServerState{} = state, %RegisterAction{action_module: module})
      when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        updated_agent = %{state.agent | actions: [module | state.agent.actions]}
        {:ok, %{state | agent: updated_agent}}

      {:error, _reason} ->
        {:error, Error.validation_error("Invalid action module", %{module: module})}
    end
  end

  def execute(%ServerState{} = _state, %RegisterAction{action_module: module}) do
    {:error, Error.validation_error("Invalid action module", %{module: module})}
  end

  def execute(%ServerState{} = state, %DeregisterAction{action_module: module})
      when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        updated_agent = %{state.agent | actions: List.delete(state.agent.actions, module)}
        {:ok, %{state | agent: updated_agent}}

      {:error, _reason} ->
        {:error, Error.validation_error("Invalid action module", %{module: module})}
    end
  end

  def execute(%ServerState{} = _state, %DeregisterAction{action_module: module}) do
    {:error, Error.validation_error("Invalid action module", %{module: module})}
  end

  def execute(%ServerState{} = state, %Spawn{module: module, args: args}) do
    child_spec = build_child_spec({module, args})

    case ServerProcess.start(state, child_spec) do
      {:ok, _pid} ->
        {:ok, state}

      {:error, reason} ->
        {:error, Error.execution_error("Failed to spawn process", %{reason: reason})}
    end
  end

  def execute(%ServerState{} = state, %Kill{pid: pid}) do
    case ServerProcess.terminate(state, pid) do
      :ok ->
        {:ok, state}

      {:error, :not_found} ->
        {:error, Error.execution_error("Process not found", %{pid: pid})}

      {:error, reason} ->
        {:error,
         Error.execution_error("Failed to terminate process", %{reason: reason, pid: pid})}
    end
  end

  def execute(_state, invalid_directive) do
    {:error, Error.validation_error("Invalid directive", %{directive: invalid_directive})}
  end

  # Private helper to build child specs
  defp build_child_spec({Task, fun}) when is_function(fun) do
    spec = %{
      id: make_ref(),
      start: {Task, :start_link, [fun]},
      restart: :temporary,
      type: :worker
    }

    spec
  end

  defp build_child_spec({module, args}) do
    {module, args}
  end
end
