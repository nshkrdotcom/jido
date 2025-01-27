defmodule Jido.Agent.Server do
  use GenServer
  use ExDbug, enabled: true

  alias Jido.Agent.Server.Execute
  alias Jido.Agent.Server.Output, as: ServerOutput
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal

  require Logger

  @default_max_queue_size 10_000
  @queue_check_interval 10_000

  def start_link(opts) do
    dbug("Starting Agent Server", opts: opts)

    with {:ok, agent} <- build_agent(opts),
         {:ok, config} <- build_config(opts, agent) do
      GenServer.start_link(
        __MODULE__,
        %ServerState{
          agent: agent,
          dispatch: config.dispatch,
          max_queue_size: config.max_queue_size,
          status: :initializing,
          verbose: config.verbose,
          mode: config.mode
        },
        name: via_tuple(config.name, config.registry)
      )
    end
  end

  def child_spec(opts) do
    id = Keyword.get(opts, :id, __MODULE__)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: 5000,
      restart: :permanent,
      type: :worker
    }
  end

  def state(pid) when is_pid(pid) do
    GenServer.call(pid, :state)
  end

  @impl true
  def init(
        %ServerState{
          agent: agent,
          dispatch: dispatch
        } = state
      ) do
    dbug("Initializing state", agent: agent, dispatch: dispatch)

    with :ok <- ServerState.validate_state(state),
         {:ok, supervisor} <- DynamicSupervisor.start_link(strategy: :one_for_one),
         {:ok, state} <- ServerState.transition(%{state | child_supervisor: supervisor}, :idle),
         # Call mount callback if defined
         {:ok, mounted_agent} <- call_mount_callback(agent, state),
         {:ok, mounted_state} <- {:ok, %{state | agent: mounted_agent}} do
      ServerOutput.emit_event(mounted_state, ServerSignal.started(), %{agent_id: mounted_agent.id})

      dbug("Server initialized successfully", state: mounted_state)
      {:ok, mounted_state}
    else
      {:error, reason} ->
        error("Failed to initialize worker", reason: reason)
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:check_queue_size, _from, %ServerState{} = state) do
    queue_size = :queue.len(state.pending_signals)

    if queue_size > state.max_queue_size do
      ServerOutput.emit_event(state, ServerSignal.queue_overflow(), %{
        queue_size: queue_size,
        max_size: state.max_queue_size
      })

      {:reply, {:error, :queue_overflow}, state}
    else
      {:reply, {:ok, queue_size}, state}
    end
  end

  def handle_call(%Signal{} = signal, _from, %ServerState{} = state) do
    if :queue.len(state.pending_signals) >= state.max_queue_size do
      ServerOutput.emit_event(state, ServerSignal.stopped(), %{reason: :queue_size_exceeded})
      {:stop, :queue_size_exceeded, {:error, :queue_full}, state}
    else
      case Execute.process_signal(state, signal) do
        {:ok, new_state} -> {:reply, {:ok, new_state}, new_state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call(_unhandled, _from, state) do
    {:reply, {:error, :unhandled_call}, state}
  end

  @impl true
  def handle_cast(%Signal{} = signal, %ServerState{} = state) do
    case Execute.process_signal(state, signal) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  def handle_cast(_unhandled, state) do
    {:reply, {:error, :unhandled_cast}, state}
  end

  @impl true
  def handle_info(%Signal{} = signal, %ServerState{} = state) do
    do_handle_info(signal, state)
  end

  def handle_info(:check_queue_size, %ServerState{} = state) do
    do_handle_info(:check_queue_size, state)
  end

  def handle_info({:EXIT, _pid, reason}, %ServerState{} = state) do
    {:stop, reason, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %ServerState{} = state) do
    ServerOutput.emit_event(state, ServerSignal.process_terminated(), %{pid: pid, reason: reason})
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    {:reply, {:error, :unhandled_info}, state}
  end

  def handle_info(_unhandled, state) do
    {:reply, {:error, :unhandled_info}, state}
  end

  defp do_handle_info(%Signal{} = signal, %ServerState{} = state) do
    if ServerSignal.is_event_signal?(signal) do
      {:noreply, state}
    else
      case Execute.process_signal(state, signal) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, reason} -> {:stop, reason, state}
      end
    end
  end

  defp do_handle_info(:check_queue_size, %ServerState{} = state) do
    if :queue.len(state.pending_signals) > state.max_queue_size do
      ServerOutput.emit_event(state, ServerSignal.queue_overflow(), %{
        queue_size: :queue.len(state.pending_signals),
        max_size: state.max_queue_size
      })

      Process.send_after(self(), :check_queue_size, @queue_check_interval)
      {:noreply, state, :hibernate}
    else
      {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, %ServerState{child_supervisor: supervisor, agent: agent} = state)
      when is_pid(supervisor) do
    dbug("Server terminating",
      reason: inspect(reason),
      agent_id: state.agent.id,
      status: state.status
    )

    # Call shutdown callback before cleanup
    shutdown_result = call_shutdown_callback(agent, reason)

    # Emit stopped signal before cleanup
    ServerOutput.emit_event(state, ServerSignal.stopped(), %{
      reason: reason,
      shutdown_result: shutdown_result
    })

    # Cleanup processes
    cleanup_processes(supervisor)

    # Return :ok to allow normal termination
    :ok
  end

  def terminate(reason, state) do
    # Emit stopped signal for non-supervisor states
    if state && state.agent && state.agent.id do
      # Try shutdown callback even without supervisor
      shutdown_result =
        if state.agent,
          do: call_shutdown_callback(state.agent, reason),
          else: :ok

      ServerOutput.emit_event(state, ServerSignal.stopped(), %{
        reason: reason,
        shutdown_result: shutdown_result
      })
    end

    # Return :ok to allow normal termination
    :ok
  end

  @impl true
  def format_status(_opts, [_pdict, state]) do
    %{
      state: state,
      status: state.status,
      agent_id: state.agent.id,
      queue_size: :queue.len(state.pending_signals),
      child_processes: DynamicSupervisor.which_children(state.child_supervisor)
    }
  end

  defp build_agent(opts) do
    case Keyword.fetch(opts, :agent) do
      {:ok, agent_input} when not is_nil(agent_input) ->
        cond do
          # Module that needs instantiation
          is_atom(agent_input) and :erlang.function_exported(agent_input, :new, 2) ->
            id = Keyword.get(opts, :id)
            initial_state = Keyword.get(opts, :initial_state, %{})
            {:ok, agent_input.new(id, initial_state)}

          # Already instantiated struct
          is_struct(agent_input) ->
            {:ok, agent_input}

          true ->
            {:error, :invalid_agent}
        end

      _ ->
        {:error, :invalid_agent}
    end
  end

  defp build_config(opts, agent) do
    try do
      {:ok,
       %{
         name: opts[:name] || agent.id,
         dispatch: Keyword.get(opts, :dispatch, {:bus, [target: :default, stream: "agent"]}),
         max_queue_size: Keyword.get(opts, :max_queue_size, @default_max_queue_size),
         registry: Keyword.get(opts, :registry, Jido.AgentRegistry),
         verbose: Keyword.get(opts, :verbose, false),
         mode: Keyword.get(opts, :mode, :auto)
       }}
    rescue
      error -> {:error, {:invalid_config, error}}
    end
  end

  # Private helper to call mount callback if defined
  defp call_mount_callback(agent, state) do
    if function_exported?(agent.__struct__, :mount, 2) do
      dbug("Calling mount callback", agent_id: agent.id)

      try do
        case agent.__struct__.mount(agent, state) do
          {:ok, mounted_agent} -> {:ok, mounted_agent}
          {:error, reason} -> {:error, {:mount_failed, reason}}
        end
      rescue
        error -> {:error, {:mount_failed, error}}
      end
    else
      {:ok, agent}
    end
  end

  # Private helper to call shutdown callback if defined
  defp call_shutdown_callback(agent, reason) do
    if function_exported?(agent.__struct__, :shutdown, 2) do
      dbug("Calling shutdown callback", agent_id: agent.id, reason: reason)

      try do
        case agent.__struct__.shutdown(agent, reason) do
          {:ok, _} -> :ok
          {:error, shutdown_error} -> {:error, {:shutdown_failed, shutdown_error}}
        end
      rescue
        error -> {:error, {:shutdown_failed, error}}
      end
    else
      :ok
    end
  end

  defp cleanup_processes(supervisor) when is_pid(supervisor) do
    try do
      DynamicSupervisor.stop(supervisor, :shutdown)
      :ok
    catch
      :exit, _ -> :ok
    end
  end

  defp via_tuple(name, registry), do: {:via, Registry, {registry, name}}
end
