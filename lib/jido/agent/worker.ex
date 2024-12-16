defmodule Jido.Agent.Worker do
  @moduledoc """
  A GenServer implementation for managing Jido agents with centralized command handling
  and pluggable communication.

  This module provides a robust worker process for Jido agents, handling:
  - Agent state management
  - Command processing and queueing
  - PubSub-based communication
  - Metrics and signal emission

  It supports various commands like replan, pause, resume, reset, and stop,
  and manages the agent's lifecycle through different states (idle, planning, running, paused).
  """

  use GenServer
  require Logger
  use Jido.Util, debug_enabled: false
  alias Jido.Signal

  @type command :: :replan | :pause | :resume | :reset | :stop
  @type agent :: Jido.Agent.t()
  @type topic :: String.t()

  defmodule State do
    @moduledoc """
    Struct module for the Agent Worker state.
    """

    @type t :: %__MODULE__{
            agent: Jido.Agent.Worker.agent(),
            pubsub: module(),
            topics: %{
              input: String.t(),
              emit: String.t(),
              metrics: String.t()
            },
            status: :idle | :planning | :running | :paused,
            config: map(),
            pending_commands: :queue.queue()
          }

    defstruct [
      :agent,
      :pubsub,
      :topics,
      status: :idle,
      config: %{act_on_input?: true},
      pending_commands: :queue.new()
    ]

    @spec default_topics(String.t()) :: %{
            input: String.t(),
            emit: String.t(),
            metrics: String.t()
          }
    def default_topics(agent_id) do
      base = "jido.agent.#{agent_id}"

      %{
        input: base,
        emit: "#{base}/emit",
        metrics: "#{base}/metrics"
      }
    end
  end

  # Client API

  @doc """
  Starts a new Agent Worker process.

  ## Options

    * `:agent` - The Jido agent to manage (required)
    * `:name` - The name to register the process under (optional, defaults to agent ID)
    * `:pubsub` - The PubSub module to use for communication (required)

  ## Returns

    * `{:ok, pid}` on success
    * `{:error, reason}` on failure
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    agent = Keyword.fetch!(opts, :agent)
    name = opts[:name] || agent.id
    pubsub = Keyword.fetch!(opts, :pubsub)

    debug("Starting Jido Agent Worker", %{agent: agent, pubsub: pubsub})

    GenServer.start_link(
      __MODULE__,
      %{agent: agent, pubsub: pubsub},
      name: via_tuple(name)
    )
  end

  @doc """
  Returns a child specification for starting the Agent Worker under a supervisor.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
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

  @doc """
  Updates the agent's attributes.

  ## Parameters

    * `server` - The GenServer reference
    * `attrs` - A map of attributes to update

  ## Returns

    * `:ok`
  """
  @spec set(GenServer.server(), map()) :: :ok
  def set(server, attrs) do
    debug("Calling set", %{server: server, attrs: attrs})
    GenServer.cast(server, {:set, attrs})
  end

  @doc """
  Triggers the agent to act based on its current state.

  ## Parameters

    * `server` - The GenServer reference
    * `attrs` - A map of additional attributes for the action

  ## Returns

    * `:ok`
  """
  @spec act(GenServer.server(), map()) :: :ok
  def act(server, attrs) do
    debug("Calling act", %{server: server, attrs: attrs})
    GenServer.cast(server, {:act, attrs})
  end

  @doc """
  Sends a command to the agent.

  ## Parameters

    * `server` - The GenServer reference
    * `command` - The command to execute
    * `args` - Additional arguments for the command (optional)

  ## Returns

    * `{:ok, State.t()}` on success
    * `{:error, term()}` on failure
  """
  @spec cmd(GenServer.server(), command(), term()) :: {:ok, State.t()} | {:error, term()}
  def cmd(server, command, args \\ nil) do
    debug("Calling cmd", %{server: server, command: command, args: args})
    GenServer.call(server, {:cmd, command, args})
  end

  # Server Callbacks

  @impl true
  @spec init(map()) :: {:ok, State.t()} | {:stop, term()}
  def init(%{agent: agent, pubsub: pubsub}) do
    debug("Initializing Jido Agent Worker", %{agent: agent, pubsub: pubsub})

    state = %State{
      agent: agent,
      pubsub: pubsub,
      topics: State.default_topics(agent.id)
    }

    with :ok <- validate_state(state),
         :ok <- subscribe_to_input(state) do
      emit_metrics(state, :started, %{agent_id: agent.id})
      {:ok, state}
    else
      {:error, reason} ->
        debug("Initialization failed", %{reason: reason})
        {:stop, reason}
    end
  end

  # Message Handlers

  @impl true
  @spec handle_cast({:set, map()} | {:act, map()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({:set, attrs}, state) do
    debug("Handling set cast", %{attrs: attrs})

    case do_set(state, attrs) do
      {:ok, new_state} ->
        debug("Set successful, processing next command")
        maybe_process_next_command(new_state)

      {:error, reason} ->
        debug("Set failed", %{reason: reason})
        {:noreply, state}
    end
  end

  def handle_cast({:act, attrs}, state) do
    debug("Handling act cast", %{attrs: attrs})

    case do_act(state, attrs) do
      {:ok, new_state} ->
        debug("Act successful, processing next command")
        maybe_process_next_command(new_state)

      {:error, reason} ->
        debug("Act failed", %{reason: reason})
        {:noreply, state}
    end
  end

  @impl true
  @spec handle_call({:cmd, command(), term()}, GenServer.from(), State.t()) ::
          {:reply, {:ok, State.t()} | {:ok, :queued} | {:error, term()}, State.t()}
  def handle_call({:cmd, command, args}, _from, state) do
    debug("Handling cmd call", %{command: command, args: args})

    case enqueue_or_execute_command(state, command, args) do
      {:execute, result, new_state} ->
        debug("Command executed immediately", %{result: result})
        {:reply, result, new_state}

      {:enqueue, new_state} ->
        debug("Command enqueued")
        {:reply, {:ok, :queued}, new_state}
    end
  end

  # PubSub Handler
  @impl true
  @spec handle_info(Jido.Signal.t() | term(), State.t()) :: {:noreply, State.t()}
  def handle_info(%Jido.Signal{} = signal, state) do
    debug("Handling incoming signal", %{type: signal.type})

    case signal.type do
      "jido.agent.set" ->
        case do_set(state, signal.data) do
          {:ok, new_state} ->
            maybe_process_next_command(new_state)

          {:error, reason} ->
            debug("Set failed", %{reason: reason})
            {:noreply, state}
        end

      "jido.agent.act" ->
        case do_act(state, signal.data) do
          {:ok, new_state} ->
            maybe_process_next_command(new_state)

          {:error, reason} ->
            debug("Act failed", %{reason: reason})
            {:noreply, state}
        end

      "jido.agent.cmd" ->
        case enqueue_or_execute_command(state, signal.data.command, signal.data.args) do
          {:execute, {:ok, new_state}, _} ->
            debug("Command executed immediately")
            {:noreply, new_state}

          {:execute, {:error, reason}, _} ->
            debug("Command execution failed", %{reason: reason})
            {:noreply, state}

          {:enqueue, new_state} ->
            debug("Command enqueued")
            {:noreply, new_state}
        end

      _ ->
        debug("Unhandled signal type", %{type: signal.type})
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    debug("Unhandled info message", %{msg: msg})
    {:noreply, state}
  end

  # Command Handling

  @spec enqueue_or_execute_command(State.t(), command(), term()) ::
          {:execute, {:ok, State.t()} | {:error, term()}, State.t()} | {:enqueue, State.t()}
  defp enqueue_or_execute_command(%{status: status} = state, :resume, args)
       when status == :paused do
    debug("Executing resume command immediately", %{args: args})

    case do_cmd(state, :resume, args) do
      {:ok, new_state} -> {:execute, {:ok, new_state}, new_state}
      error -> {:execute, error, state}
    end
  end

  defp enqueue_or_execute_command(%{status: :idle} = state, command, args) do
    debug("Executing command immediately", %{command: command, args: args})

    case do_cmd(state, command, args) do
      {:ok, new_state} ->
        {:execute, {:ok, new_state}, new_state}

      error ->
        debug("Command execution failed", %{error: error})
        {:execute, error, state}
    end
  end

  defp enqueue_or_execute_command(state, command, args) do
    debug("Enqueuing command", %{command: command, args: args})
    new_state = %{state | pending_commands: :queue.in({command, args}, state.pending_commands)}
    {:enqueue, new_state}
  end

  @spec maybe_process_next_command(State.t()) :: {:noreply, State.t()}
  defp maybe_process_next_command(%{status: :idle, pending_commands: queue} = state) do
    debug("Processing next command")

    case :queue.out(queue) do
      {{:value, {command, args}}, new_queue} ->
        debug("Executing next command", %{command: command, args: args})
        new_state = %{state | pending_commands: new_queue}

        case do_cmd(new_state, command, args) do
          {:ok, final_state} ->
            {:noreply, final_state}

          {:error, reason} ->
            debug("Command execution failed", %{reason: reason})
            {:noreply, new_state}
        end

      {:empty, _queue} ->
        debug("No pending commands")
        {:noreply, state}
    end
  end

  defp maybe_process_next_command(state) do
    debug("Not processing next command", %{status: state.status})
    {:noreply, state}
  end

  # Core Command Handlers

  @spec do_set(State.t(), map() | nil) :: {:ok, State.t()} | {:error, String.t()}
  defp do_set(%State{status: :paused} = state, _attrs) do
    debug("Set ignored due to paused state")
    {:ok, state}
  end

  defp do_set(%State{} = state, nil) do
    debug("Set failed: nil attrs not allowed")
    emit_signal(state, :set_failed, %{error: "nil attrs not allowed"})
    {:error, "nil attrs not allowed"}
  end

  defp do_set(%State{agent: agent} = state, attrs) when is_map(attrs) do
    debug("Performing set", %{attrs: attrs})

    case agent.__struct__.set(agent, attrs) do
      {:ok, updated_agent} ->
        new_state = %{state | agent: updated_agent}
        emit_signal(new_state, :set_processed, %{attrs: attrs})

        if state.config.act_on_input? do
          debug("Performing automatic act")

          case do_act(new_state, %{}) do
            {:ok, final_state} ->
              {:ok, final_state}

            {:error, reason} ->
              debug("Automatic act failed", %{reason: reason})
              emit_signal(state, :auto_act_failed, %{error: reason})
              {:ok, new_state}
          end
        else
          {:ok, new_state}
        end

      {:error, reason} = error ->
        debug("Set failed", %{reason: reason})
        emit_signal(state, :set_failed, %{error: reason, attrs: attrs})
        error
    end
  end

  @spec do_act(State.t(), map()) :: {:ok, State.t()} | {:error, term()}
  defp do_act(%State{status: :paused} = state, _attrs) do
    debug("Act ignored due to paused state")
    {:ok, state}
  end

  defp do_act(%State{agent: agent, status: status} = state, attrs)
       when status in [:idle, :running] do
    debug("Performing act", %{attrs: attrs})

    case agent.__struct__.act(agent, attrs) do
      {:ok, updated_agent} ->
        emit_signal(state, :act_completed, %{
          initial_state: agent,
          final_state: updated_agent
        })

        {:ok, %{state | agent: updated_agent, status: :idle}}

      {:error, reason} = error ->
        debug("Act failed", %{reason: reason})
        emit_signal(state, :act_failed, %{error: reason})
        error
    end
  end

  @spec do_cmd(State.t(), command(), term()) :: {:ok, State.t()} | {:error, term()}
  defp do_cmd(state, command, args) do
    debug("Executing command", %{command: command, args: args})

    case execute_command(state, command, args) do
      {:ok, new_state} = result ->
        emit_signal(new_state, :"#{command}_completed", %{args: args})
        result

      {:error, reason} = error ->
        debug("Command execution failed", %{reason: reason})
        emit_signal(state, :"#{command}_failed", %{error: reason})
        error
    end
  end

  @spec execute_command(State.t(), command(), term()) :: {:ok, State.t()} | {:error, term()}
  defp execute_command(state, :pause, _args) do
    debug("Executing pause command")
    {:ok, %{state | status: :paused}}
  end

  defp execute_command(state, :resume, _args) do
    debug("Executing resume command")
    {:ok, %{state | status: :running}}
  end

  defp execute_command(%{agent: agent} = state, :reset, _args) do
    debug("Executing reset command")

    case agent.__struct__.new(agent.id) do
      %{} = new_agent ->
        {:ok, %{state | agent: new_agent, status: :idle}}

      error ->
        debug("Reset failed", %{error: error})
        {:error, error}
    end
  end

  defp execute_command(state, :replan, _args) do
    debug("Executing replan command")
    {:ok, %{state | status: :idle}}
  end

  defp execute_command(state, :stop, _args) do
    debug("Executing stop command")
    emit_signal(state, :stopped, %{})
    {:ok, %{state | status: :stopped}}
  end

  defp execute_command(_state, command, _args) do
    debug("Unknown command", %{command: command})
    {:error, {:unknown_command, command}}
  end

  # Private Helper Functions

  @spec validate_state(State.t()) :: :ok | {:error, String.t()}
  defp validate_state(%State{pubsub: nil}), do: {:error, "PubSub module is required"}
  defp validate_state(%State{agent: nil}), do: {:error, "Agent is required"}
  defp validate_state(_state), do: :ok

  @spec subscribe_to_input(State.t()) :: :ok
  defp subscribe_to_input(%State{pubsub: pubsub, topics: topics}) do
    debug("Subscribing to input topic", %{topic: topics.input})
    Phoenix.PubSub.subscribe(pubsub, topics.input)
  end

  @spec emit_signal(State.t(), atom(), map()) :: :ok
  defp emit_signal(%State{} = state, event_type, payload) do
    debug("Emitting signal", %{event_type: event_type, payload: payload})

    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.#{event_type}",
        source: "/agent/#{state.agent.id}",
        data: payload
      })

    broadcast_event(state, :emit, signal)
  end

  @spec emit_metrics(State.t(), atom(), map()) :: :ok
  defp emit_metrics(%State{} = state, event_type, payload) do
    debug("Emitting metrics", %{event_type: event_type, payload: payload})

    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.#{event_type}",
        source: "/agent/#{state.agent.id}",
        data: payload
      })

    broadcast_event(state, :metrics, signal)
  end

  @spec broadcast_event(State.t(), atom(), term()) :: :ok
  defp broadcast_event(%State{pubsub: pubsub, topics: topics}, channel, payload) do
    topic = Map.get(topics, channel)
    debug("Broadcasting event", %{channel: channel, topic: topic})
    Phoenix.PubSub.broadcast(pubsub, topic, payload)
  end

  @spec via_tuple(term()) :: {:via, Registry, {Jido.AgentRegistry, term()}}
  defp via_tuple(name) do
    {:via, Registry, {Jido.AgentRegistry, name}}
  end
end
