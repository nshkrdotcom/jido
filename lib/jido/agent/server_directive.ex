defmodule Jido.Agent.Server.Directive do
  @moduledoc false
  # Executes validated directives within an agent server context.

  # This module handles applying directive structs to modify server state and behavior.
  # Only directives defined in Jido.Agent.Directive are valid.

  alias Jido.Agent.Server.Process, as: ServerProcess
  alias Jido.Agent.Server.State, as: ServerState

  alias Jido.Agent.Directive.{
    Spawn,
    Kill
  }

  alias Jido.{Agent.Directive, Error}

  @doc """
  Processes one or more directives against a server state.

  Takes a ServerState and a list of directives, executing each in sequence and
  returning the final updated state.

  ## Parameters
    - state: Current server state
    - directives: Single directive or list of directives to process

  ## Returns
    - `{:ok, updated_state}` - All directives executed successfully
    - `{:error, Error.t()}` - Failed to execute a directive

  ## Examples

      # Process a single directive
      {:ok, state} = Directive.handle(state, %Spawn{module: MyWorker})

      # Process multiple directives
      {:ok, state} = Directive.handle(state, [
        %Spawn{module: Worker1},
        %Spawn{module: Worker2}
      ])
  """
  @spec handle(ServerState.t(), Directive.t() | [Directive.t()]) ::
          {:ok, ServerState.t()} | {:error, Error.t()}
  def handle(%ServerState{} = state, directives) when is_list(directives) do
    Enum.reduce_while(directives, {:ok, state}, fn directive, {:ok, acc_state} ->
      case execute(acc_state, directive) do
        {:ok, new_state} -> {:cont, {:ok, new_state}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def handle(%ServerState{} = state, directive) do
    execute(state, directive)
  end

  @doc """
  Executes a validated directive within a server context.

  Takes a ServerState and a Directive struct, and applies the directive's operation
  to modify the server state appropriately.

  ## Parameters
    - state: Current server state
    - directive: The directive to execute

  ## Returns
    - `{:ok, updated_state}` - Directive executed successfully
    - `{:error, Error.t()}` - Failed to execute directive

  ## Examples

      # Execute a spawn directive
      {:ok, state} = Directive.execute(state, %Spawn{module: MyWorker, args: [id: 1]})

      # Execute a kill directive
      {:ok, state} = Directive.execute(state, %Kill{pid: worker_pid})
  """
  @spec execute(ServerState.t(), Directive.t()) :: {:ok, ServerState.t()} | {:error, Error.t()}

  def execute(%ServerState{} = state, %Spawn{module: module, args: args}) do
    child_spec = build_child_spec({module, args})

    case ServerProcess.start(state, child_spec) do
      {:ok, state, _pid} ->
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

  # Private helper to build child specs for process spawning
  #
  # Takes a tuple of {module, args} or {Task, function} and returns a proper child spec
  # for use with DynamicSupervisor.
  #
  # ## Parameters
  #   - {Task, fun} - For task-based processes where fun is a function
  #   - {module, args} - For module-based processes with initialization args
  #
  # ## Returns
  #   - A proper child specification map or tuple
  defp build_child_spec({Task, fun}) when is_function(fun) do
    %{
      id: make_ref(),
      start: {Task, :start_link, [fun]},
      restart: :temporary,
      type: :worker
    }
  end

  defp build_child_spec({module, args}) do
    {module, args}
  end
end
