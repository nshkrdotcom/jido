defmodule Jido.Agent.Runtime do
  use GenServer
  use Private
  use Jido.Util, debug_enabled: false

  alias Jido.Agent.Runtime.Execute
  alias Jido.Agent.Runtime.PubSub
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  alias Jido.Agent.Runtime.State, as: RuntimeState
  alias Jido.Signal

  require Logger

  @default_max_queue_size 10_000
  @queue_check_interval 10_000

  # Start the runtime
  def start_link(opts) do
    with {:ok, agent} <- build_agent(opts),
         {:ok, agent} <- validate_agent(agent),
         {:ok, config} <- build_config(opts, agent) do
      debug("Starting Agent", name: config.name, pubsub: config.pubsub, topic: config.topic)

      GenServer.start_link(
        __MODULE__,
        %{
          agent: agent,
          pubsub: config.pubsub,
          topic: config.topic,
          max_queue_size: config.max_queue_size
        },
        name: via_tuple(config.name, config.registry)
      )
    end
  end

  def child_spec(opts) do
    debug("Creating child spec", opts: opts)
    id = Keyword.get(opts, :id, __MODULE__)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: 5000,
      restart: :permanent,
      type: :worker
    }
  end

  # Public API
  def cmd(server, action, args \\ %{}, opts \\ []) do
    {:ok, id} = get_id(server)
    GenServer.call(server, RuntimeSignal.action_to_signal(id, action, args, opts))
  end

  def get_id(server) do
    get_state_field(server, & &1.agent.id)
  end

  def get_topic(server) do
    get_state_field(server, & &1.topic)
  end

  def get_status(server) do
    get_state_field(server, & &1.status)
  end

  def get_supervisor(server) do
    get_state_field(server, & &1.child_supervisor)
  end

  def get_state(server) do
    get_state_field(server, & &1)
  end

  # GenServer callbacks
  @impl true
  def init(%{agent: agent, pubsub: pubsub, topic: topic, max_queue_size: max_queue_size}) do
    debug("Initializing state", agent: agent, pubsub: pubsub, topic: topic)

    state = %RuntimeState{
      agent: agent,
      pubsub: pubsub,
      topic: topic || PubSub.generate_topic(agent.id),
      status: :initializing,
      max_queue_size: max_queue_size
    }

    with :ok <- RuntimeState.validate_state(state),
         :ok <- PubSub.subscribe(state),
         {:ok, supervisor} <- DynamicSupervisor.start_link(strategy: :one_for_one),
         {:ok, running_state} <-
           RuntimeState.transition(%{state | child_supervisor: supervisor}, :idle) do
      PubSub.emit(running_state, RuntimeSignal.started(), %{agent_id: agent.id})
      debug("Runtime initialized successfully", state: running_state)
      {:ok, running_state}
    else
      {:error, reason} ->
        error("Failed to initialize worker", reason: reason)
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(%Signal{} = signal, _from, %RuntimeState{} = state) do
    debug("Handling cmd signal", signal: signal)

    if :queue.len(state.pending) >= state.max_queue_size do
      {:reply, {:error, :queue_full}, state}
    else
      case Execute.process_signal(state, signal) do
        {:ok, new_state} -> {:reply, {:ok, new_state}, new_state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call(unhandled, _from, state) do
    error("Unhandled call", unhandled: unhandled)
    {:reply, {:error, :unhandled_call}, state}
  end

  @impl true
  def handle_cast(%Signal{} = signal, %RuntimeState{} = state) do
    debug("Handling cast signal", signal: signal)

    case Execute.process_signal(state, signal) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  def handle_cast(unhandled, state) do
    error("Unhandled cast", unhandled: unhandled)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Signal{} = signal, %RuntimeState{} = state) do
    if RuntimeSignal.is_event_signal?(signal) do
      {:noreply, state}
    else
      case Execute.process_signal(state, signal) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, reason} -> {:stop, reason, state}
      end
    end
  end

  def handle_info(:check_queue_size, state) do
    if :queue.len(state.pending) > state.max_queue_size do
      Process.send_after(self(), :check_queue_size, @queue_check_interval)
      {:noreply, state, :hibernate}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    debug("Child process down", pid: pid, reason: reason)
    # Handle child process termination
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    debug("Received timeout")
    {:noreply, state}
  end

  def handle_info(unhandled, state) do
    error("Unhandled info", unhandled: unhandled)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %RuntimeState{child_supervisor: supervisor} = state)
      when is_pid(supervisor) do
    debug("Runtime terminating",
      reason: inspect(reason),
      agent_id: state.agent.id,
      status: state.status
    )

    with :ok <- PubSub.emit(state, RuntimeSignal.stopped(), %{reason: reason}),
         :ok <- cleanup_processes(supervisor),
         :ok <- PubSub.unsubscribe(state) do
      :ok
    else
      error ->
        error("Cleanup failed during termination", error: error)
        :ok
    end
  end

  def terminate(_reason, _state), do: :ok

  @impl true
  def format_status(_reason, [_pdict, state]) do
    %{
      state: state,
      status: state.status,
      agent_id: state.agent.id,
      queue_size: :queue.len(state.pending),
      child_processes: DynamicSupervisor.which_children(state.child_supervisor)
    }
  end

  defp build_agent(opts) do
    case Keyword.fetch(opts, :agent) do
      {:ok, agent_input} when not is_nil(agent_input) ->
        if is_atom(agent_input) and :erlang.function_exported(agent_input, :new, 0) do
          {:ok, agent_input.new()}
        else
          {:ok, agent_input}
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
         pubsub: Keyword.fetch!(opts, :pubsub),
         topic: Keyword.get(opts, :topic, PubSub.generate_topic(agent.id)),
         max_queue_size: Keyword.get(opts, :max_queue_size, @default_max_queue_size),
         registry: Keyword.get(opts, :registry, Jido.AgentRegistry)
       }}
    rescue
      KeyError -> {:error, :missing_pubsub}
    end
  end

  defp validate_agent(agent) when is_map(agent) and is_binary(agent.id), do: {:ok, agent}
  defp validate_agent(_), do: {:error, :invalid_agent}

  defp get_state_field(server, field_fn) do
    case GenServer.call(server, :get_state) do
      {:ok, state} -> {:ok, field_fn.(state)}
      error -> error
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
