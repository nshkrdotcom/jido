defmodule Jido.AgentServer.State do
  @moduledoc """
  Internal state for AgentServer GenServer.

  > #### Internal Module {: .warning}
  > This module is internal to the AgentServer implementation. Its API may
  > change without notice. Use `Jido.AgentServer.state/1` to retrieve state.

  This struct holds all runtime state for an agent instance including
  the agent itself, directive queue, hierarchy tracking, and configuration.
  """

  alias Jido.AgentServer.{ChildInfo, Options}
  alias Jido.AgentServer.State.Lifecycle, as: LifecycleState

  @type status :: :initializing | :idle | :processing | :stopping

  @schema Zoi.struct(
            __MODULE__,
            %{
              # Core identity
              id: Zoi.string(description: "Instance ID"),
              agent_module: Zoi.atom(description: "Agent module"),
              agent: Zoi.any(description: "The Jido.Agent struct"),

              # Status and processing
              status:
                Zoi.atom(description: "Current server status") |> Zoi.default(:initializing),
              processing:
                Zoi.boolean(description: "Whether currently processing directives")
                |> Zoi.default(false),
              queue:
                Zoi.any(description: "Directive queue (:queue.queue())")
                |> Zoi.default(:queue.new()),

              # Hierarchy
              parent: Zoi.any(description: "Parent reference") |> Zoi.optional(),
              parent_monitor_ref:
                Zoi.any(description: "Monitor reference for parent process") |> Zoi.optional(),
              children: Zoi.map(description: "Map of tag => ChildInfo") |> Zoi.default(%{}),
              child_monitors:
                Zoi.map(description: "Map of child monitor ref => child tag") |> Zoi.default(%{}),
              child_pids:
                Zoi.map(description: "Map of child pid => child tag") |> Zoi.default(%{}),
              on_parent_death:
                Zoi.atom(description: "Behavior on parent death") |> Zoi.default(:stop),

              # Cron jobs
              cron_jobs:
                Zoi.map(description: "Map of job_id => scheduler job name") |> Zoi.default(%{}),
              skip_schedules:
                Zoi.boolean(description: "Skip registering plugin schedules")
                |> Zoi.default(false),

              # Configuration
              jido: Zoi.atom(description: "Jido instance name (required)"),
              default_dispatch: Zoi.any(description: "Default dispatch config") |> Zoi.optional(),
              error_policy:
                Zoi.any(description: "Error handling policy") |> Zoi.default(:log_only),
              max_queue_size: Zoi.integer(description: "Max queue size") |> Zoi.default(10_000),
              registry: Zoi.atom(description: "Registry module"),
              spawn_fun: Zoi.any(description: "Custom spawn function") |> Zoi.optional(),

              # Routing
              signal_router:
                Zoi.any(description: "Jido.Signal.Router for signal routing")
                |> Zoi.optional(),

              # Observability
              error_count:
                Zoi.integer(description: "Count of errors for max_errors policy")
                |> Zoi.default(0),
              metrics: Zoi.map(description: "Runtime metrics") |> Zoi.default(%{}),
              completion_waiters:
                Zoi.map(description: "Map of ref => waiter for completion notifications")
                |> Zoi.default(%{}),
              scheduled_timers:
                Zoi.map(description: "Map of timer ref => timer metadata") |> Zoi.default(%{}),

              # Lifecycle (InstanceManager integration: attachment tracking, idle timeout, persistence)
              lifecycle: Zoi.any(description: "Lifecycle state (State.Lifecycle.t())"),

              # Debug mode
              debug:
                Zoi.boolean(description: "Whether debug mode is enabled") |> Zoi.default(false),
              debug_events:
                Zoi.list(Zoi.any(), description: "Ring buffer of debug events (max 50)")
                |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new State from validated Options, agent module, and agent struct.

  If a parent reference is provided, it's injected into the agent's state
  as `agent.state.__parent__` so agents can use `Directive.emit_to_parent/3`.
  """
  @spec from_options(Options.t(), module(), struct()) :: {:ok, t()} | {:error, term()}
  def from_options(%Options{} = opts, agent_module, agent) do
    agent = inject_parent_into_agent(agent, opts.parent)

    lifecycle_opts = [
      lifecycle_mod: opts.lifecycle_mod,
      pool: opts.pool,
      pool_key: opts.pool_key,
      idle_timeout: opts.idle_timeout,
      persistence: opts.persistence
    ]

    with {:ok, lifecycle} <- LifecycleState.new(lifecycle_opts) do
      attrs = %{
        id: opts.id,
        agent_module: agent_module,
        agent: agent,
        status: :initializing,
        processing: false,
        queue: :queue.new(),
        parent: opts.parent,
        parent_monitor_ref: nil,
        children: %{},
        child_monitors: %{},
        child_pids: %{},
        on_parent_death: opts.on_parent_death,
        jido: opts.jido,
        default_dispatch: opts.default_dispatch,
        error_policy: opts.error_policy,
        max_queue_size: opts.max_queue_size,
        registry: opts.registry,
        spawn_fun: opts.spawn_fun,
        cron_jobs: %{},
        skip_schedules: opts.skip_schedules,
        error_count: 0,
        metrics: %{},
        completion_waiters: %{},
        scheduled_timers: %{},
        lifecycle: lifecycle,
        debug: opts.debug,
        debug_events: []
      }

      Zoi.parse(@schema, attrs)
    end
  end

  defp inject_parent_into_agent(agent, nil), do: agent

  defp inject_parent_into_agent(agent, parent) do
    updated_state = Map.put(agent.state, :__parent__, parent)
    %{agent | state: updated_state}
  end

  @doc """
  Updates the agent in state.
  """
  @spec update_agent(t(), struct()) :: t()
  def update_agent(%__MODULE__{} = state, agent) do
    %{state | agent: agent}
  end

  @doc """
  Sets the status.
  """
  @spec set_status(t(), status()) :: t()
  def set_status(%__MODULE__{} = state, status)
      when status in [:initializing, :idle, :processing, :stopping] do
    %{state | status: status}
  end

  @doc """
  Enqueues a directive with its triggering signal for later execution.
  """
  @spec enqueue(t(), Jido.Signal.t(), struct()) :: {:ok, t()} | {:error, :queue_overflow}
  def enqueue(%__MODULE__{queue: queue, max_queue_size: max} = state, signal, directive) do
    if :queue.len(queue) >= max do
      {:error, :queue_overflow}
    else
      {:ok, %{state | queue: :queue.in({signal, directive}, queue)}}
    end
  end

  @doc """
  Enqueues multiple directives from a single signal.
  """
  @spec enqueue_all(t(), Jido.Signal.t(), [struct()]) :: {:ok, t()} | {:error, :queue_overflow}
  def enqueue_all(state, _signal, []), do: {:ok, state}

  def enqueue_all(%__MODULE__{} = state, signal, [directive | rest]) do
    case enqueue(state, signal, directive) do
      {:ok, new_state} -> enqueue_all(new_state, signal, rest)
      error -> error
    end
  end

  @doc """
  Dequeues the next directive for processing.
  """
  @spec dequeue(t()) :: {{:value, {Jido.Signal.t(), struct()}}, t()} | {:empty, t()}
  def dequeue(%__MODULE__{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        {{:value, item}, %{state | queue: new_queue}}

      {:empty, _} ->
        {:empty, state}
    end
  end

  @doc """
  Returns the current queue length.
  """
  @spec queue_length(t()) :: non_neg_integer()
  def queue_length(%__MODULE__{queue: queue}) do
    :queue.len(queue)
  end

  @doc """
  Checks if the queue is empty.
  """
  @spec queue_empty?(t()) :: boolean()
  def queue_empty?(%__MODULE__{queue: queue}) do
    :queue.is_empty(queue)
  end

  @doc """
  Adds a child to the children map.
  """
  @spec add_child(t(), term(), ChildInfo.t()) :: t()
  def add_child(
        %__MODULE__{children: children, child_monitors: child_monitors, child_pids: child_pids} =
          state,
        tag,
        %ChildInfo{} = child
      ) do
    %{
      state
      | children: Map.put(children, tag, child),
        child_monitors: maybe_put_child_monitor(child_monitors, child.ref, tag),
        child_pids: Map.put(child_pids, child.pid, tag)
    }
  end

  @doc """
  Removes a child by tag.
  """
  @spec remove_child(t(), term()) :: t()
  def remove_child(
        %__MODULE__{children: children, child_monitors: child_monitors, child_pids: child_pids} =
          state,
        tag
      ) do
    case Map.pop(children, tag) do
      {nil, _children} ->
        state

      {%ChildInfo{} = child, remaining_children} ->
        %{
          state
          | children: remaining_children,
            child_monitors: maybe_delete_child_monitor(child_monitors, child.ref),
            child_pids: Map.delete(child_pids, child.pid)
        }
    end
  end

  @doc """
  Removes a child by PID.
  """
  @spec remove_child_by_pid(t(), pid()) :: {term() | nil, t()}
  def remove_child_by_pid(%__MODULE__{child_pids: child_pids} = state, pid) do
    case Map.get(child_pids, pid) do
      nil -> {nil, state}
      tag -> {tag, remove_child(state, tag)}
    end
  end

  @doc """
  Removes a child by monitor reference.
  """
  @spec remove_child_by_ref(t(), reference()) :: {term() | nil, t()}
  def remove_child_by_ref(%__MODULE__{child_monitors: child_monitors} = state, ref)
      when is_reference(ref) do
    case Map.get(child_monitors, ref) do
      nil -> {nil, state}
      tag -> {tag, remove_child(state, tag)}
    end
  end

  @doc """
  Looks up a child tag by PID.
  """
  @spec child_tag_by_pid(t(), pid()) :: term() | nil
  def child_tag_by_pid(%__MODULE__{child_pids: child_pids}, pid) do
    Map.get(child_pids, pid)
  end

  @doc """
  Adds a scheduled timer ref for cleanup.
  """
  @spec add_scheduled_timer(t(), reference(), map()) :: t()
  def add_scheduled_timer(%__MODULE__{scheduled_timers: timers} = state, ref, meta)
      when is_reference(ref) and is_map(meta) do
    %{state | scheduled_timers: Map.put(timers, ref, meta)}
  end

  @doc """
  Removes a scheduled timer ref.
  """
  @spec remove_scheduled_timer(t(), reference()) :: t()
  def remove_scheduled_timer(%__MODULE__{scheduled_timers: timers} = state, ref)
      when is_reference(ref) do
    %{state | scheduled_timers: Map.delete(timers, ref)}
  end

  @doc """
  Prunes fired or cancelled timers from tracking.
  """
  @spec prune_scheduled_timers(t()) :: t()
  def prune_scheduled_timers(%__MODULE__{scheduled_timers: timers} = state) do
    alive_timers =
      Enum.reduce(timers, %{}, fn {ref, meta}, acc ->
        case :erlang.read_timer(ref) do
          remaining when is_integer(remaining) and remaining >= 0 ->
            Map.put(acc, ref, meta)

          _ ->
            acc
        end
      end)

    %{state | scheduled_timers: alive_timers}
  end

  @doc """
  Gets a child by tag.
  """
  @spec get_child(t(), term()) :: ChildInfo.t() | nil
  def get_child(%__MODULE__{children: children}, tag) do
    Map.get(children, tag)
  end

  defp maybe_put_child_monitor(monitors, ref, tag) when is_reference(ref) do
    Map.put(monitors, ref, tag)
  end

  defp maybe_put_child_monitor(monitors, _ref, _tag), do: monitors

  defp maybe_delete_child_monitor(monitors, ref) when is_reference(ref) do
    Map.delete(monitors, ref)
  end

  defp maybe_delete_child_monitor(monitors, _ref), do: monitors

  @doc """
  Increments the error count.
  """
  @spec increment_error_count(t()) :: t()
  def increment_error_count(%__MODULE__{error_count: count} = state) do
    %{state | error_count: count + 1}
  end

  # Debug mode constants
  @max_debug_events 50

  @doc """
  Records a debug event if debug mode is enabled.

  Events are stored in a ring buffer (max #{@max_debug_events} entries).
  Each event includes a monotonic timestamp for relative timing.
  """
  @spec record_debug_event(t(), atom(), map()) :: t()
  def record_debug_event(%__MODULE__{debug: false} = state, _type, _data), do: state

  def record_debug_event(%__MODULE__{debug: true, debug_events: events} = state, type, data) do
    event = %{
      at: System.monotonic_time(:millisecond),
      type: type,
      data: data
    }

    # Keep only last N events (ring buffer behavior)
    new_events = Enum.take([event | events], @max_debug_events)
    %{state | debug_events: new_events}
  end

  @doc """
  Returns recent debug events, newest first.

  ## Options

  - `:limit` - Maximum number of events to return (default: all)
  """
  @spec get_debug_events(t(), keyword()) :: [map()]
  def get_debug_events(%__MODULE__{debug_events: events}, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    case limit do
      nil -> events
      n when is_integer(n) and n > 0 -> Enum.take(events, n)
      _ -> events
    end
  end

  @doc """
  Enables or disables debug mode at runtime.
  """
  @spec set_debug(t(), boolean()) :: t()
  def set_debug(%__MODULE__{} = state, enabled) when is_boolean(enabled) do
    %{state | debug: enabled}
  end
end
