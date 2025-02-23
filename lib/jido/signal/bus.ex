defmodule Jido.Signal.Bus do
  use GenServer
  require Logger
  use ExDbug, enabled: true
  use TypedStruct
  alias Jido.Signal.Router
  alias Jido.Signal.Bus.BusState
  alias Jido.Signal.Bus.Stream
  alias Jido.Signal.Bus.Snapshot

  @type start_option ::
          {:name, atom()}
          | {atom(), term()}

  @type server ::
          pid() | atom() | binary() | {name :: atom() | binary(), registry :: module()}
  @type path :: Router.path()
  @type subscription_id :: String.t()
  # typedstruct module: Subscriber do
  #   field(:id, String.t(), default: Jido.Util.generate_id())
  #   field(:dispatch, Dispatch.t())
  # end

  @doc """
  Starts a new bus process.
  Options:
  - name: The name to register the bus under (required)
  - router: A custom router implementation (optional)
  """
  @impl GenServer
  def init({name, opts}) do
    dbug("init", name: name, opts: opts)
    # Trap exits so we can handle subscriber termination
    Process.flag(:trap_exit, true)

    state = %BusState{
      id: Jido.Util.generate_id(),
      name: name,
      router: Keyword.get(opts, :router, Router.new!()),
      route_signals: Keyword.get(opts, :route_signals, false),
      config: opts
    }

    {:ok, state}
  end

  @spec resolve_pid(server()) :: {:ok, pid()} | {:error, :server_not_found}
  def resolve_pid(pid) when is_pid(pid) do
    dbug("resolve_pid", pid: pid)
    {:ok, pid}
  end

  def resolve_pid({name, registry})
      when (is_atom(name) or is_binary(name)) and is_atom(registry) do
    dbug("resolve_pid", name: name, registry: registry)
    name = if is_atom(name), do: Atom.to_string(name), else: name

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def resolve_pid(name) when is_atom(name) or is_binary(name) do
    dbug("resolve_pid", name: name)
    name = if is_atom(name), do: Atom.to_string(name), else: name
    resolve_pid({name, Jido.Bus.Registry})
  end

  def start_link(opts) do
    dbug("start_link", opts: opts)
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, {name, opts}, name: via_tuple(name, opts))
  end

  def via_tuple(name, opts \\ []) do
    dbug("via_tuple", name: name, opts: opts)
    registry = Keyword.get(opts, :registry, Jido.Bus.Registry)
    {:via, Registry, {registry, name}}
  end

  def whereis(name, opts \\ []) do
    dbug("whereis", name: name, opts: opts)
    registry = Keyword.get(opts, :registry, Jido.Bus.Registry)

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Subscribes to signals matching the given path pattern.
  Options:
  - dispatch: How to dispatch signals to the subscriber (default: async to calling process)
  """
  @spec subscribe(server(), path(), Keyword.t()) :: {:ok, subscription_id()} | {:error, term()}
  def subscribe(bus, path, opts \\ []) do
    opts =
      if Enum.empty?(opts) do
        [dispatch: {:pid, target: self(), delivery_mode: :async}]
      else
        opts
      end

    with {:ok, pid} <- resolve_pid(bus) do
      GenServer.call(pid, {:subscribe, path, opts})
    end
  end

  @doc """
  Unsubscribes from signals using the subscription ID.
  """
  @spec unsubscribe(server(), subscription_id()) :: :ok | {:error, term()}
  def unsubscribe(bus, subscription_id) do
    with {:ok, pid} <- resolve_pid(bus) do
      GenServer.call(pid, {:unsubscribe, subscription_id})
    end
  end

  @doc """
  Publishes a list of signals to the bus.
  Returns {:ok, recorded_signals} on success.
  """
  @spec publish(server(), [Jido.Signal.t()]) ::
          {:ok, [Jido.Signal.Bus.RecordedSignal.t()]} | {:error, term()}
  def publish(bus, signals) when is_list(signals) do
    with {:ok, pid} <- resolve_pid(bus) do
      GenServer.call(pid, {:publish, signals})
    end
  end

  @doc """
  Replays signals from the bus log that match the given path pattern.
  Optional start_timestamp to replay from a specific point in time.
  """
  @spec replay(server(), path(), non_neg_integer(), Keyword.t()) ::
          {:ok, [Jido.Signal.Bus.RecordedSignal.t()]} | {:error, term()}
  def replay(bus, path \\ "*", start_timestamp \\ 0, opts \\ []) do
    with {:ok, pid} <- resolve_pid(bus) do
      GenServer.call(pid, {:replay, path, start_timestamp, opts})
    end
  end

  @doc """
  Creates a new snapshot of signals matching the given path pattern.
  """
  @spec snapshot_create(server(), path()) :: {:ok, Snapshot.SnapshotRef.t()} | {:error, term()}
  def snapshot_create(bus, path) do
    with {:ok, pid} <- resolve_pid(bus) do
      GenServer.call(pid, {:snapshot_create, path})
    end
  end

  @doc """
  Lists all available snapshots.
  """
  @spec snapshot_list(server()) :: [Snapshot.SnapshotRef.t()]
  def snapshot_list(bus) do
    with {:ok, pid} <- resolve_pid(bus) do
      GenServer.call(pid, :snapshot_list)
    end
  end

  @doc """
  Reads a snapshot by its ID.
  """
  @spec snapshot_read(server(), String.t()) :: {:ok, Snapshot.SnapshotData.t()} | {:error, term()}
  def snapshot_read(bus, snapshot_id) do
    with {:ok, pid} <- resolve_pid(bus) do
      GenServer.call(pid, {:snapshot_read, snapshot_id})
    end
  end

  @doc """
  Deletes a snapshot by its ID.
  """
  @spec snapshot_delete(server(), String.t()) :: :ok | {:error, term()}
  def snapshot_delete(bus, snapshot_id) do
    with {:ok, pid} <- resolve_pid(bus) do
      GenServer.call(pid, {:snapshot_delete, snapshot_id})
    end
  end

  @impl GenServer
  def handle_call({:subscribe, path, opts}, _from, state) do
    subscription_id = Keyword.get(opts, :subscription_id, Jido.Util.generate_id())
    dispatch = Keyword.get(opts, :dispatch)
    persistent = Keyword.get(opts, :persistent, false)

    case Jido.Signal.Bus.Subscriber.subscribe(state, subscription_id, path, dispatch,
           persistent: persistent
         ) do
      {:ok, new_state} -> {:reply, {:ok, subscription_id}, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    case Jido.Signal.Bus.Subscriber.unsubscribe(state, subscription_id) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:publish, signals}, _from, state) do
    case Stream.publish(state, signals) do
      {:ok, recorded_signals, new_state} -> {:reply, {:ok, recorded_signals}, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:replay, path, start_timestamp, opts}, _from, state) do
    case Stream.filter(state, path, start_timestamp, opts) do
      {:ok, signals} -> {:reply, {:ok, signals}, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:snapshot_create, path}, _from, state) do
    case Snapshot.create(state, path) do
      {:ok, snapshot_ref, new_state} -> {:reply, {:ok, snapshot_ref}, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call(:snapshot_list, _from, state) do
    {:reply, Snapshot.list(state), state}
  end

  def handle_call({:snapshot_read, snapshot_id}, _from, state) do
    case Snapshot.read(state, snapshot_id) do
      {:ok, snapshot_data} -> {:reply, {:ok, snapshot_data}, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:snapshot_delete, snapshot_id}, _from, state) do
    case Snapshot.delete(state, snapshot_id) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    dbug("handle_info :DOWN", pid: pid, reason: reason, state: state)
    # Remove the subscriber if it dies
    case Enum.find(state.subscribers, fn {_id, sub_pid} -> sub_pid == pid end) do
      nil ->
        {:noreply, state}

      {subscriber_id, _} ->
        Logger.info("Subscriber #{subscriber_id} terminated with reason: #{inspect(reason)}")
        {_, new_subscribers} = Map.pop(state.subscribers, subscriber_id)
        {:noreply, %{state | subscribers: new_subscribers}}
    end
  end

  def handle_info(msg, state) do
    dbug("handle_info", msg: msg, state: state)
    Logger.debug("Unexpected message in Bus: #{inspect(msg)}")
    {:noreply, state}
  end
end
