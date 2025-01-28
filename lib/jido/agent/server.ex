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
      dbug("Agent and config built successfully", agent: agent, config: config)

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
    dbug("Building child spec", opts: opts)
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
    dbug("Getting server state", pid: pid)
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
      dbug("State validation successful", state: state)
      dbug("Supervisor started", supervisor: supervisor)
      dbug("State transitioned to idle")
      dbug("Agent mounted successfully", mounted_agent: mounted_agent)

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
    dbug("Handling state request", current_state: state)
    {:reply, {:ok, state}, state}
  end

  def handle_call(:check_queue_size, _from, %ServerState{} = state) do
    queue_size = :queue.len(state.pending_signals)
    dbug("Checking queue size", current_size: queue_size, max_size: state.max_queue_size)

    if queue_size > state.max_queue_size do
      dbug("Queue overflow detected", queue_size: queue_size)

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
    dbug("Handling signal call", signal: signal, state: state)

    if :queue.len(state.pending_signals) >= state.max_queue_size do
      dbug("Queue size exceeded, stopping server", queue_size: :queue.len(state.pending_signals))
      ServerOutput.emit_event(state, ServerSignal.stopped(), %{reason: :queue_size_exceeded})
      {:stop, :queue_size_exceeded, {:error, :queue_full}, state}
    else
      dbug("Processing signal", signal: signal)

      case Execute.process_signal(state, signal) do
        {:ok, new_state} ->
          dbug("Signal processed successfully", new_state: new_state)
          {:reply, {:ok, new_state}, new_state}

        {:error, reason} ->
          dbug("Signal processing failed", error: reason)
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call(_unhandled, _from, state) do
    dbug("Received unhandled call", unhandled: _unhandled, state: state)
    {:reply, {:error, :unhandled_call}, state}
  end

  @impl true
  def handle_cast(%Signal{} = signal, %ServerState{} = state) do
    dbug("Handling signal cast", signal: signal, state: state)

    case Execute.process_signal(state, signal) do
      {:ok, new_state} ->
        dbug("Cast signal processed successfully", new_state: new_state)
        {:noreply, new_state}

      {:error, reason} ->
        dbug("Cast signal processing failed", error: reason)
        {:stop, reason, state}
    end
  end

  def handle_cast(_unhandled, state) do
    dbug("Received unhandled cast", state: state)
    {:reply, {:error, :unhandled_cast}, state}
  end

  @impl true
  def handle_info(%Signal{} = signal, %ServerState{} = state) do
    dbug("Handling info signal", signal: signal, state: state)
    do_handle_info(signal, state)
  end

  def handle_info(:check_queue_size, %ServerState{} = state) do
    dbug("Handling queue size check", state: state)
    do_handle_info(:check_queue_size, state)
  end

  def handle_info({:EXIT, _pid, reason}, %ServerState{} = state) do
    dbug("Handling EXIT message", reason: reason, state: state)
    {:stop, reason, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %ServerState{} = state) do
    dbug("Handling DOWN message", pid: pid, reason: reason, state: state)
    ServerOutput.emit_event(state, ServerSignal.process_terminated(), %{pid: pid, reason: reason})
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    dbug("Handling timeout", state: state)
    {:reply, {:error, :unhandled_info}, state}
  end

  def handle_info(_unhandled, state) do
    dbug("Received unhandled info", state: state)
    {:reply, {:error, :unhandled_info}, state}
  end

  defp do_handle_info(%Signal{} = signal, %ServerState{} = state) do
    dbug("Processing info signal", signal: signal, state: state)

    if ServerSignal.is_event_signal?(signal) do
      dbug("Ignoring event signal")
      {:noreply, state}
    else
      case Execute.process_signal(state, signal) do
        {:ok, new_state} ->
          dbug("Info signal processed successfully", new_state: new_state)
          {:noreply, new_state}

        {:error, reason} ->
          dbug("Info signal processing failed", error: reason)
          {:stop, reason, state}
      end
    end
  end

  defp do_handle_info(:check_queue_size, %ServerState{} = state) do
    queue_size = :queue.len(state.pending_signals)
    dbug("Checking queue size", current_size: queue_size, max_size: state.max_queue_size)

    if queue_size > state.max_queue_size do
      dbug("Queue overflow detected", queue_size: queue_size)

      ServerOutput.emit_event(state, ServerSignal.queue_overflow(), %{
        queue_size: queue_size,
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
    dbug("Calling shutdown callback")
    shutdown_result = call_shutdown_callback(agent, reason)
    dbug("Shutdown callback completed", result: shutdown_result)

    # Emit stopped signal before cleanup
    dbug("Emitting stopped signal")

    ServerOutput.emit_event(state, ServerSignal.stopped(), %{
      reason: reason,
      shutdown_result: shutdown_result
    })

    # Cleanup processes
    dbug("Cleaning up processes")
    cleanup_processes(supervisor)

    # Return :ok to allow normal termination
    :ok
  end

  def terminate(reason, state) do
    dbug("Terminating without supervisor", reason: reason, state: state)
    # Emit stopped signal for non-supervisor states
    if state && state.agent && state.agent.id do
      # Try shutdown callback even without supervisor
      dbug("Attempting shutdown callback without supervisor")

      shutdown_result =
        if state.agent,
          do: call_shutdown_callback(state.agent, reason),
          else: :ok

      dbug("Shutdown result", result: shutdown_result)

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
    dbug("Formatting status", state: state)

    %{
      state: state,
      status: state.status,
      agent_id: state.agent.id,
      queue_size: :queue.len(state.pending_signals),
      child_processes: DynamicSupervisor.which_children(state.child_supervisor)
    }
  end

  defp build_agent(opts) do
    dbug("Building agent", opts: opts)

    case Keyword.fetch(opts, :agent) do
      {:ok, agent_input} when not is_nil(agent_input) ->
        cond do
          # Module that needs instantiation
          is_atom(agent_input) and :erlang.function_exported(agent_input, :new, 2) ->
            dbug("Instantiating new agent from module", module: agent_input)
            id = Keyword.get(opts, :id)
            initial_state = Keyword.get(opts, :initial_state, %{})
            {:ok, agent_input.new(id, initial_state)}

          # Already instantiated struct
          is_struct(agent_input) ->
            dbug("Using pre-instantiated agent struct")
            {:ok, agent_input}

          true ->
            dbug("Invalid agent input")
            {:error, :invalid_agent}
        end

      _ ->
        dbug("Missing agent input")
        {:error, :invalid_agent}
    end
  end

  defp build_config(opts, agent) do
    dbug("Building config", opts: opts, agent: agent)

    try do
      config = %{
        name: opts[:name] || agent.id,
        dispatch: Keyword.get(opts, :dispatch, {:bus, [target: :default, stream: "agent"]}),
        max_queue_size: Keyword.get(opts, :max_queue_size, @default_max_queue_size),
        registry: Keyword.get(opts, :registry, Jido.AgentRegistry),
        verbose: Keyword.get(opts, :verbose, false),
        mode: Keyword.get(opts, :mode, :auto)
      }

      dbug("Config built successfully", config: config)
      {:ok, config}
    rescue
      error ->
        dbug("Config build failed", error: error)
        {:error, {:invalid_config, error}}
    end
  end

  # Private helper to call mount callback if defined
  defp call_mount_callback(agent, state) do
    if function_exported?(agent.__struct__, :mount, 2) do
      dbug("Calling mount callback", agent_id: agent.id)

      try do
        case agent.__struct__.mount(agent, state) do
          {:ok, mounted_agent} ->
            dbug("Mount successful", mounted_agent: mounted_agent)
            {:ok, mounted_agent}

          {:error, reason} ->
            dbug("Mount failed", error: reason)
            {:error, {:mount_failed, reason}}
        end
      rescue
        error ->
          dbug("Mount callback raised error", error: error)
          {:error, {:mount_failed, error}}
      end
    else
      dbug("No mount callback defined")
      {:ok, agent}
    end
  end

  # Private helper to call shutdown callback if defined
  defp call_shutdown_callback(agent, reason) do
    if function_exported?(agent.__struct__, :shutdown, 2) do
      dbug("Calling shutdown callback", agent_id: agent.id, reason: reason)

      try do
        case agent.__struct__.shutdown(agent, reason) do
          {:ok, _} ->
            dbug("Shutdown successful")
            :ok

          {:error, shutdown_error} ->
            dbug("Shutdown failed", error: shutdown_error)
            {:error, {:shutdown_failed, shutdown_error}}
        end
      rescue
        error ->
          dbug("Shutdown callback raised error", error: error)
          {:error, {:shutdown_failed, error}}
      end
    else
      dbug("No shutdown callback defined")
      :ok
    end
  end

  defp cleanup_processes(supervisor) when is_pid(supervisor) do
    dbug("Cleaning up supervisor processes", supervisor: supervisor)

    try do
      DynamicSupervisor.stop(supervisor, :shutdown)
      dbug("Supervisor stopped successfully")
      :ok
    catch
      :exit, reason ->
        dbug("Supervisor cleanup failed", error: reason)
        :ok
    end
  end

  defp via_tuple(name, registry) do
    dbug("Building via tuple", name: name, registry: registry)
    {:via, Registry, {registry, name}}
  end
end
