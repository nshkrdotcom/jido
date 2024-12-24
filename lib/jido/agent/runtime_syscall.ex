defmodule Jido.Agent.Runtime.Syscall do
  @moduledoc """
  Defines and handles system calls that agents can use to interact with their runtime environment.

  Syscalls provide controlled access to runtime operations like process management, command
  scheduling, and state manipulation. Each syscall is validated and executed within the
  context of the calling agent's runtime.

  ## Categories

  - Process Management: Spawn, monitor, and terminate child processes
  - Command Control: Schedule and manage command execution
  - State Management: Access and modify runtime state
  - Communication: Inter-process and inter-runtime messaging
  - Resource Management: Acquire and release runtime resources
  """

  alias Jido.Agent.Runtime.Process, as: RuntimeProcess
  alias Jido.Agent.Runtime.State, as: RuntimeState
  alias Jido.Agent.Runtime.PubSub
  alias Jido.Signal
  use Jido.Util, debug_enabled: true

  @type child_spec ::
          {:task, function()}
          | module()
          | {module(), term()}
          | {module(), term(), atom() | nil}

  # Process Management
  @type syscall ::
          {:spawn, child_spec()}
          | {:kill, pid()}
          | {:kill_all}

          # Command Queue
          | {:enqueue, atom(), map()}
          | {:reset_queue}
          | {:pause}
          | {:resume}

          # PubSub
          | {:subscribe, atom()}
          | {:unsubscribe, atom()}

  @type result ::
          {:ok, pid()}
          | :ok
          | {:error, term()}

  @doc """
  Executes a syscall within the context of a runtime.

  Returns either a success tuple with any relevant data or an error tuple.
  All syscalls are logged for auditing and debugging purposes.
  """
  @spec execute(RuntimeState.t(), syscall()) :: {result(), RuntimeState.t()}

  def execute(%RuntimeState{} = state, {:spawn, spec}) do
    {module, child_spec} = build_child_spec(spec)

    debug("Spawning child process", module: module, child_spec: child_spec)

    case RuntimeProcess.start(state, child_spec) do
      {:ok, _pid} = result -> {result, state}
      error -> {error, state}
    end
  end

  def execute(%RuntimeState{} = state, {:kill, pid_or_name}) do
    case RuntimeProcess.terminate(state, pid_or_name) do
      :ok ->
        maybe_unregister(pid_or_name)
        {:ok, state}

      {:error, :not_found} ->
        {{:error, :not_found}, state}

      error ->
        {error, state}
    end
  end

  def execute(%RuntimeState{} = state, {:kill_all}) do
    debug("Terminating all child processes")

    RuntimeProcess.list(state)
    |> Enum.each(fn {_, pid, _, _} ->
      RuntimeProcess.terminate(state, pid)
    end)

    {:ok, state}
  end

  def execute(%RuntimeState{} = state, {:enqueue, cmd, params}) do
    debug("Enqueueing command", command: cmd, params: params)

    with {:ok, signal} <-
           Signal.new(%{
             type: "jido.agent.cmd",
             source: "/agent/#{state.agent.id}",
             data: %{command: cmd, args: params}
           }),
         {:ok, new_state} <- RuntimeState.enqueue(state, signal) do
      {:ok, new_state}
    else
      error -> {error, state}
    end
  end

  def execute(%RuntimeState{} = state, :reset_queue) do
    case RuntimeState.clear_queue(state) do
      {:ok, new_state} -> {:ok, new_state}
      error -> {error, state}
    end
  end

  def execute(%RuntimeState{status: :running} = state, :pause) do
    case RuntimeState.transition(state, :paused) do
      {:ok, new_state} -> {:ok, new_state}
      error -> {error, state}
    end
  end

  def execute(%RuntimeState{status: :paused} = state, :resume) do
    case RuntimeState.transition(state, :idle) do
      {:ok, new_state} -> {:ok, new_state}
      error -> {error, state}
    end
  end

  def execute(%RuntimeState{} = state, {:subscribe, _topic}) do
    case PubSub.subscribe(state) do
      :ok -> {:ok, state}
      error -> {error, state}
    end
  end

  def execute(%RuntimeState{} = state, {:unsubscribe, _topic}) do
    case PubSub.unsubscribe(state) do
      :ok -> {:ok, state}
      error -> {error, state}
    end
  end

  def execute(%RuntimeState{} = state, invalid_syscall) do
    debug("Invalid syscall attempted",
      syscall: invalid_syscall,
      level: :warning
    )

    {{:error, :invalid_syscall}, state}
  end

  # Private helper to build child specs
  defp build_child_spec({:task, fun}) when is_function(fun) do
    spec = %{
      id: Jido.Util.generate_id(),
      start: {Task, :start_link, [fun]},
      restart: :temporary,
      type: :worker
    }

    {Task, spec}
  end

  defp build_child_spec({module, args}) do
    {module, {module, args}}
  end

  defp build_child_spec({module, args, name}) when is_atom(name) do
    spec = %{
      id: module,
      start: {module, :start_link, [args, [name: name]]}
    }

    {module, spec}
  end

  defp build_child_spec(module) when is_atom(module) do
    {module, module}
  end

  defp maybe_unregister(name) when is_atom(name), do: Process.unregister(name)
  defp maybe_unregister(_), do: :ok
end
