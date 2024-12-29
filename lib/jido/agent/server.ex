defmodule Jido.Agent.Server do
  @moduledoc """
  A fault-tolerant, distributed agent server implementation that manages stateful agents
  with built-in pub/sub capabilities and dynamic supervision.

  The `Jido.Agent.Server` provides a robust framework for managing long-running agent processes
  with the following key features:

    * Automatic pub/sub event distribution via configurable PubSub adapter
    * Dynamic supervision of child processes
    * Configurable queue size limits and backpressure handling
    * Graceful shutdown and cleanup of resources
    * Comprehensive state management and transition handling
    * Registry-based process naming for distributed operations

  ## Usage

  To start an agent server:

      {:ok, pid} = Jido.Agent.Server.start_link([
        agent: MyAgent.new(),
        pubsub: MyApp.PubSub,
        name: "my_agent",
        max_queue_size: 5_000
      ])

  The server can then receive commands via the `cmd/4` function:

      Jido.Agent.Server.cmd(pid, :some_action, %{arg: "value"}, [])

  ## Configuration Options

    * `:agent` - Required. The agent struct or module implementing `new/0`
    * `:pubsub` - Required. The PubSub module for event distribution
    * `:name` - Optional. The registration name (defaults to agent.id)
    * `:topic` - Optional. The PubSub topic (defaults to generated from agent.id)
    * `:max_queue_size` - Optional. Maximum pending signals (defaults to 10,000)
    * `:registry` - Optional. The Registry for process registration (defaults to Jido.AgentRegistry)

  ## Supervision

  The server automatically supervises child processes using a `:one_for_one` DynamicSupervisor
  strategy. Each child process is monitored and can be restarted independently.

  ## State Management

  The server maintains its state through the `Jido.Agent.Server.State` struct and handles
  transitions via signal processing. State transitions are validated and published as events.

  ## Signal Processing

  Commands and events are processed as signals through the `Execute` module, which handles:

    * Action signals (synchronous commands)
    * Event signals (asynchronous notifications)
    * State transitions
    * Queue management

  ## Fault Tolerance

  The server implements comprehensive error handling and cleanup:

    * Graceful termination with resource cleanup
    * Automatic unsubscription from PubSub topics
    * Child process shutdown management
    * Queue size monitoring and backpressure

  See `cmd/4` for sending commands and `get_state/1` for retrieving current server state.
  """
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

  @doc """
  Starts a new Agent Server process linked to the current process.

  Initializes the server with the given agent and configuration, subscribes to relevant
  PubSub topics, and starts a DynamicSupervisor for managing child processes.

  ## Parameters

    * `opts` - Keyword list of server options:
      * `:agent` - Required. Agent struct or module implementing `new/0`
      * `:pubsub` - Required. PubSub module for event distribution
      * `:name` - Optional. Registration name (defaults to agent.id)
      * `:topic` - Optional. PubSub topic (defaults to generated from agent.id)
      * `:max_queue_size` - Optional. Maximum pending signals (defaults to 10,000)
      * `:registry` - Optional. Registry for process registration (defaults to Jido.AgentRegistry)

  ## Returns

    * `{:ok, pid}` - Successfully started server process
    * `{:error, reason}` - Failed to start server

  ## Error Reasons

    * `:invalid_agent` - Agent is nil or invalid
    * `:missing_pubsub` - PubSub module not provided
    * `:already_started` - Server already registered with given name
    * Any error from PubSub subscription or DynamicSupervisor start

  ## Examples

      # Start with minimal configuration
      {:ok, pid} = Jido.Agent.Server.start_link([
        agent: MyAgent.new(),
        pubsub: MyApp.PubSub
      ])

      # Start with full configuration
      {:ok, pid} = Jido.Agent.Server.start_link([
        agent: MyAgent.new(),
        pubsub: MyApp.PubSub,
        name: "custom_agent",
        topic: "agents:custom",
        max_queue_size: 5_000,
        registry: MyApp.Registry
      ])

  ## Runtime Behavior

  The server performs these steps during initialization:
  1. Validates agent and builds configuration
  2. Starts DynamicSupervisor for child processes
  3. Subscribes to configured PubSub topic
  4. Transitions to :idle state
  5. Emits 'started' event

  The process is registered via the configured Registry using the :via tuple
  pattern for distributed process lookup.
  """
  @spec start_link([start_opt()]) :: GenServer.on_start()
  def start_link(opts) do
    with {:ok, agent} <- build_agent(opts),
         {:ok, agent} <- validate_agent(agent),
         {:ok, config} <- build_config(opts, agent) do
      dbug("Starting Agent", name: config.name, pubsub: config.pubsub, topic: config.topic)

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

  @doc false
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

  # Public API

  @doc """
  Sends a command to the agent server for processing.

  ## Parameters
    * `server` - The server process identifier
    * `action` - The action module to execute
    * `args` - Optional map of arguments for the action (default: %{})
    * `opts` - Optional keyword list of options (default: [])

  ## Returns
    * `{:ok, state}` - Command processed successfully with updated state
    * `{:error, reason}` - Command failed with reason
  """
  @spec cmd(GenServer.server(), module(), map(), keyword()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def cmd(server, action, args \\ %{}, opts \\ []) do
    {:ok, id} = get_id(server)
    GenServer.call(server, ServerSignal.action_signal(id, action, args, opts))
  end

  @doc """
  Gets the agent ID from the server state.

  ## Parameters
    * `server` - The server process identifier

  ## Returns
    * `{:ok, id}` - The agent ID string
    * `{:error, reason}` - Failed to get ID
  """
  @spec get_id(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def get_id(server) do
    get_state_field(server, & &1.agent.id)
  end

  @doc """
  Gets the PubSub topic from the server state.

  ## Parameters
    * `server` - The server process identifier

  ## Returns
    * `{:ok, topic}` - The PubSub topic string
    * `{:error, reason}` - Failed to get topic
  """
  @spec get_topic(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def get_topic(server) do
    get_state_field(server, & &1.topic)
  end

  @doc """
  Gets the current status from the server state.

  ## Parameters
    * `server` - The server process identifier

  ## Returns
    * `{:ok, status}` - The current server status
    * `{:error, reason}` - Failed to get status
  """
  @spec get_status(GenServer.server()) :: {:ok, atom()} | {:error, term()}
  def get_status(server) do
    get_state_field(server, & &1.status)
  end

  @doc """
  Gets the child supervisor PID from the server state.

  ## Parameters
    * `server` - The server process identifier

  ## Returns
    * `{:ok, pid}` - The supervisor PID
    * `{:error, reason}` - Failed to get supervisor
  """
  @spec get_supervisor(GenServer.server()) :: {:ok, pid()} | {:error, term()}
  def get_supervisor(server) do
    get_state_field(server, & &1.child_supervisor)
  end

  @doc """
  Gets the complete server state.

  ## Parameters
    * `server` - The server process identifier

  ## Returns
    * `{:ok, state}` - The complete server state
    * `{:error, reason}` - Failed to get state
  """
  @spec get_state(GenServer.server()) :: {:ok, ServerState.t()} | {:error, term()}
  def get_state(server) do
    get_state_field(server, & &1)
  end

  # GenServer callbacks

  @doc """
  Initializes the server state with the provided configuration.

  ## Parameters
    * `%{agent:, pubsub:, topic:, max_queue_size:}` - The initialization map containing:
      * `agent` - The agent struct to manage
      * `pubsub` - The PubSub module for event distribution
      * `topic` - Optional topic override (defaults to agent ID based topic)
      * `max_queue_size` - Maximum pending signals allowed

  ## Returns
    * `{:ok, state}` - Successfully initialized with the server state
    * `{:stop, reason}` - Failed to initialize with error reason
  """
  @impl true
  def init(%{agent: agent, pubsub: pubsub, topic: topic, max_queue_size: max_queue_size}) do
    dbug("Initializing state", agent: agent, pubsub: pubsub, topic: topic)

    state = %ServerState{
      agent: agent,
      pubsub: pubsub,
      topic: topic || PubSub.generate_topic(agent.id),
      status: :initializing,
      max_queue_size: max_queue_size
    }

    with :ok <- ServerState.validate_state(state),
         {:ok, state} <- PubSub.subscribe(state, state.topic),
         {:ok, supervisor} <- DynamicSupervisor.start_link(strategy: :one_for_one),
         {:ok, running_state} <-
           ServerState.transition(%{state | child_supervisor: supervisor}, :idle) do
      PubSub.emit_event(running_state, ServerSignal.started(), %{agent_id: agent.id})
      dbug("Server initialized successfully", state: running_state)
      {:ok, running_state}
    else
      {:error, reason} ->
        error("Failed to initialize worker", reason: reason)
        {:stop, reason}
    end
  end

  @doc """
  Handles synchronous calls to the server.

  ## Call Patterns
    * `:get_state` - Returns the complete server state
    * `%Signal{}` - Processes a signal synchronously if queue not full
    * Other - Returns unhandled call error

  ## Returns
    * `{:reply, reply, new_state}` - Response and updated state
    * `{:reply, {:error, reason}, state}` - Error response
  """
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

  @doc """
  Handles asynchronous casts to the server.

  ## Cast Patterns
    * `%Signal{}` - Processes a signal asynchronously
    * Other - Logs unhandled cast

  ## Returns
    * `{:noreply, new_state}` - Updated state after processing
    * `{:stop, reason, state}` - Stops server on error
  """
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

  @doc """
  Handles messages sent to the server process.

  ## Message Patterns
    * `%Signal{}` - Processes non-event signals
    * `:check_queue_size` - Monitors queue size and hibernates if needed
    * `{:DOWN, ...}` - Handles child process termination
    * `:timeout` - Handles timeout messages
    * Other - Logs unhandled messages

  ## Returns
    * `{:noreply, new_state}` - Updated state after processing
    * `{:stop, reason, state}` - Stops server on error
  """
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

  @doc """
  Handles cleanup when the server is terminating.

  Performs the following cleanup:
    * Emits stopped event
    * Stops child supervisor
    * Unsubscribes from topics

  ## Parameters
    * `reason` - The reason for termination
    * `state` - The current server state

  ## Returns
    * `:ok` - Cleanup completed (even if some steps failed)
  """
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

  @doc """
  Formats the server state for debugging.

  Returns a map containing:
    * Current state
    * Server status
    * Agent ID
    * Queue size
    * Child process information
  """
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
