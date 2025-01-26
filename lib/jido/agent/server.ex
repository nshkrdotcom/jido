defmodule Jido.Agent.Server do
  use GenServer
  use ExDbug, enabled: false

  alias Jido.Agent.Server.Execute
  alias Jido.Agent.Server.PubSub
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal

  require Logger

  @default_max_queue_size 10_000
  @queue_check_interval 10_000

  @type start_opt ::
          {:agent, struct() | module()}
          | {:pubsub, module()}
          | {:name, String.t() | atom()}
          | {:topic, String.t()}
          | {:max_queue_size, pos_integer()}
          | {:registry, module()}

  @spec start_link([start_opt()]) :: GenServer.on_start()
  def start_link(opts) do
    dbug("Starting Agent Server", opts: opts)

    with {:ok, agent} <- build_agent(opts),
         _ <- IO.inspect(agent, label: "Agent"),
         {:ok, agent} <- validate_agent(agent),
         _ <- IO.inspect(agent, label: "Validated Agent"),
         {:ok, config} <- build_config(opts, agent) do
      # dbug("Starting Agent", name: config.name, pubsub: config.pubsub, topic: config.topic)

      GenServer.start_link(
        __MODULE__,
        %{
          agent: agent,
          # pubsub: config.pubsub,
          # topic: config.topic,
          max_queue_size: config.max_queue_size
        },
        name: via_tuple(config.name, config.registry)
      )
    end
  end

  def child_spec(opts) do
    dbug("Creating child spec", opts: opts)
    id = Keyword.get(opts, :id, __MODULE__)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: 5000,
      restart: :permanent,
      type: :worker
    }
  end

  @spec cmd(GenServer.server(), module(), map(), keyword()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def cmd(server, action, args \\ %{}, opts \\ []) do
    {:ok, id} = get_id(server)
    GenServer.call(server, ServerSignal.action_signal(id, action, args, opts))
  end

  @spec get_id(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def get_id(server) do
    get_state_field(server, & &1.agent.id)
  end

  @spec get_topic(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def get_topic(server) do
    get_state_field(server, & &1.topic)
  end

  @spec get_status(GenServer.server()) :: {:ok, atom()} | {:error, term()}
  def get_status(server) do
    get_state_field(server, & &1.status)
  end

  @spec get_supervisor(GenServer.server()) :: {:ok, pid()} | {:error, term()}
  def get_supervisor(server) do
    get_state_field(server, & &1.child_supervisor)
  end

  @spec get_state(GenServer.server()) :: {:ok, ServerState.t()} | {:error, term()}
  def get_state(server) do
    get_state_field(server, & &1)
  end

  @impl true
  def init(%{agent: agent, max_queue_size: max_queue_size}) do
    # dbug("Initializing state", agent: agent, pubsub: pubsub, topic: topic)

    # state = %ServerState{
    #   agent: agent,
    #   pubsub: pubsub,
    #   topic: topic || PubSub.generate_topic(agent.id),
    #   status: :initializing,
    #   max_queue_size: max_queue_size
    # }

    # with :ok <- ServerState.validate_state(state),
    #      {:ok, state} <- PubSub.subscribe(state, state.topic),
    #      {:ok, supervisor} <- DynamicSupervisor.start_link(strategy: :one_for_one),
    #      {:ok, running_state} <-
    #        ServerState.transition(%{state | child_supervisor: supervisor}, :idle) do
    #   PubSub.emit_event(running_state, ServerSignal.started(), %{agent_id: agent.id})
    #   dbug("Server initialized successfully", state: running_state)
    #   {:ok, running_state}
    # else
    #   {:error, reason} ->
    #     error("Failed to initialize worker", reason: reason)
    #     {:stop, reason}
    # end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(%Signal{} = signal, _from, %ServerState{} = state) do
    dbug("Handling cmd signal", signal: signal)

    if :queue.len(state.pending_signals) >= state.max_queue_size do
      {:reply, {:error, :queue_full}, state}
    else
      case Execute.process_signal(state, signal) do
        {:ok, new_state} -> {:reply, {:ok, new_state}, new_state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call(_unhandled, _from, state) do
    error("Unhandled call", unhandled: _unhandled)
    {:reply, {:error, :unhandled_call}, state}
  end

  @impl true
  def handle_cast(%Signal{} = signal, %ServerState{} = state) do
    dbug("Handling cast signal", signal: signal)

    case Execute.process_signal(state, signal) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  def handle_cast(_unhandled, state) do
    error("Unhandled cast")
    {:noreply, state}
  end

  @impl true
  def handle_info(%Signal{} = signal, %ServerState{} = state) do
    if ServerSignal.is_event_signal?(signal) do
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

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    dbug("Child process down")
    # Handle child process termination
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    dbug("Received timeout")
    {:noreply, state}
  end

  def handle_info(_unhandled, state) do
    error("Unhandled info")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %ServerState{child_supervisor: supervisor} = state)
      when is_pid(supervisor) do
    dbug("Server terminating",
      reason: inspect(reason),
      agent_id: state.agent.id,
      status: state.status
    )

    with :ok <- PubSub.emit_event(state, ServerSignal.stopped(), %{reason: reason}),
         :ok <- cleanup_processes(supervisor),
         :ok <- Enum.each([state.topic | state.subscriptions], &PubSub.unsubscribe(state, &1)) do
      :ok
    else
      _error ->
        error("Cleanup failed during termination")
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
         #  pubsub: Keyword.fetch!(opts, :pubsub),
         #  topic: Keyword.get(opts, :topic, PubSub.generate_topic(agent.id)),
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
