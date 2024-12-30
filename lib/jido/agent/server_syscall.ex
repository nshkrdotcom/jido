defmodule Jido.Agent.Server.Syscall do
  @moduledoc false
  # Executes validated syscalls within an agent server context.

  # This module handles applying syscall structs to modify server state and behavior.
  # Only syscalls defined in Jido.Agent.Syscall are valid.

  alias Jido.Agent.Server.Process, as: ServerProcess
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.PubSub

  alias Jido.Agent.Syscall.{
    SpawnSyscall,
    KillSyscall,
    BroadcastSyscall,
    SubscribeSyscall,
    UnsubscribeSyscall
  }

  alias Jido.{Agent.Syscall, Error}
  use ExDbug, enabled: false

  @doc """
  Executes a validated syscall within a server context.

  Returns a tuple containing the result and updated server state.
  """
  @spec execute(ServerState.t(), Syscall.t()) :: {:ok, ServerState.t()} | {:error, Error.t()}

  def execute(%ServerState{} = state, %SpawnSyscall{module: module, args: args}) do
    child_spec = build_child_spec({module, args})

    case ServerProcess.start(state, child_spec) do
      {:ok, _pid} ->
        {:ok, state}

      {:error, reason} ->
        {:error, Error.execution_error("Failed to spawn process", %{reason: reason})}
    end
  end

  def execute(%ServerState{} = state, %KillSyscall{pid: pid}) do
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

  def execute(%ServerState{} = state, %BroadcastSyscall{topic: topic, message: msg}) do
    if is_nil(state.pubsub) do
      {:error, Error.execution_error("PubSub not configured", %{})}
    else
      case Phoenix.PubSub.broadcast(state.pubsub, topic, msg) do
        :ok ->
          {:ok, state}

        {:error, reason} ->
          {:error,
           Error.execution_error("Failed to broadcast message", %{reason: reason, topic: topic})}
      end
    end
  end

  def execute(%ServerState{} = state, %SubscribeSyscall{topic: topic}) do
    case PubSub.subscribe(state, topic) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, reason} ->
        {:error, Error.execution_error("Failed to subscribe", %{reason: reason, topic: topic})}
    end
  end

  def execute(%ServerState{} = state, %UnsubscribeSyscall{topic: topic}) do
    case PubSub.unsubscribe(state, topic) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, reason} ->
        {:error, Error.execution_error("Failed to unsubscribe", %{reason: reason, topic: topic})}
    end
  end

  def execute(_state, invalid_syscall) do
    {:error, Error.validation_error("Invalid syscall", %{syscall: invalid_syscall})}
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
