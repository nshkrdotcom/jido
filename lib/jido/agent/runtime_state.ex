defmodule Jido.Agent.Runtime.State do
  @moduledoc """
  Defines the state management structure and transition logic for Agent Runtimes.

  The Runtime.State module implements a finite state machine (FSM) that governs
  the lifecycle of agent workers in the Jido system. It ensures type safety and
  enforces valid state transitions while providing telemetry and logging for
  observability.

  ## State Machine

  The worker can be in one of the following states:
  - `:initializing` - Initial state when worker is starting up
  - `:idle` - Runtime is inactive and ready to accept new commands
  - `:planning` - Runtime is planning but not yet executing actions
  - `:running` - Runtime is actively executing commands
  - `:paused` - Runtime execution is temporarily suspended

  ## State Transitions

  Valid state transitions are:
  ```
  initializing -> idle        (initialization_complete)
  idle         -> planning    (plan_initiated)
  idle         -> running     (direct_execution)
  planning     -> running     (plan_completed)
  planning     -> idle        (plan_cancelled)
  running      -> paused      (execution_paused)
  running      -> idle        (execution_completed)
  paused       -> running     (execution_resumed)
  paused       -> idle        (execution_cancelled)
  ```

  ## Fields

  - `:agent` - The Agent struct being managed by this worker (required)
  - `:pubsub` - PubSub module for event broadcasting (required)
  - `:topic` - PubSub topic for worker events (required)
  - `:status` - Current state of the worker (default: :idle)
  - `:pending` - Queue of pending commands awaiting execution
  - `:max_queue_size` - Maximum number of commands that can be queued (default: 10000)
  - `:child_supervisor` - Dynamic supervisor PID for managing child processes

  ## Example

      iex> state = %Runtime.State{
      ...>   agent: my_agent,
      ...>   pubsub: MyApp.PubSub,
      ...>   topic: "agent.worker.1",
      ...>   status: :idle
      ...> }
      iex> {:ok, new_state} = Runtime.State.transition(state, :running)
      iex> new_state.status
      :running
  """

  use TypedStruct
  require Logger
  alias Jido.Signal
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  alias Jido.Agent.Runtime.PubSub, as: PubSub
  use Jido.Util, debug_enabled: false

  @typedoc """
  Represents the possible states of a worker.

  - `:initializing` - Runtime is starting up
  - `:idle` - Runtime is inactive
  - `:planning` - Runtime is planning actions
  - `:running` - Runtime is executing actions
  - `:paused` - Runtime execution is suspended
  """
  @type status :: :initializing | :idle | :planning | :running | :paused

  typedstruct do
    field(:agent, Jido.Agent.t(), enforce: true)
    field(:pubsub, module(), enforce: true)
    field(:topic, String.t(), enforce: true)
    field(:status, status(), default: :idle)
    field(:pending, :queue.queue(), default: :queue.new())
    field(:max_queue_size, non_neg_integer(), default: 10_000)
    field(:child_supervisor, pid())
  end

  # Define valid state transitions and their conditions
  @transitions %{
    initializing: %{
      idle: :initialization_complete
    },
    idle: %{
      idle: :already_idle,
      planning: :plan_initiated,
      running: :direct_execution
    },
    planning: %{
      running: :plan_completed,
      idle: :plan_cancelled
    },
    running: %{
      paused: :execution_paused,
      idle: :execution_completed
    },
    paused: %{
      running: :execution_resumed,
      idle: :execution_cancelled
    }
  }

  @doc """
  Attempts to transition the worker to a new state.

  This function enforces the state machine rules defined in @transitions.
  It logs state transitions for debugging and monitoring purposes.

  ## Parameters

  - `state` - Current Runtime.State struct
  - `desired` - Desired target state

  ## Returns

  - `{:ok, new_state}` - Transition was successful
  - `{:error, {:invalid_transition, current, desired}}` - Invalid state transition

  ## Examples

      iex> state = %Runtime.State{status: :idle}
      iex> Runtime.State.transition(state, :running)
      {:ok, %Runtime.State{status: :running}}

      iex> state = %Runtime.State{status: :idle}
      iex> Runtime.State.transition(state, :paused)
      {:error, {:invalid_transition, :idle, :paused}}
  """
  @spec transition(%__MODULE__{status: status()}, status()) ::
          {:ok, %__MODULE__{}} | {:error, {:invalid_transition, status(), status()}}
  def transition(%__MODULE__{status: current} = state, desired) do
    case @transitions[current][desired] do
      nil ->
        PubSub.emit(state, RuntimeSignal.transition_failed(), %{from: current, to: desired})
        {:error, {:invalid_transition, current, desired}}

      reason ->
        debug(
          "Agent state transition from #{current} to #{desired} (#{reason}) for agent #{state.agent.id}"
        )

        PubSub.emit(state, RuntimeSignal.transition_succeeded(), %{from: current, to: desired})

        {:ok, %{state | status: desired}}
    end
  end

  @doc """
  Enqueues a signal into the state's pending queue.

  Validates that the queue size is within the configured maximum before adding.
  Emits a queue_overflow event if the queue is full.

  ## Parameters

  - `state` - Current runtime state
  - `signal` - Signal to enqueue

  ## Returns

  - `{:ok, new_state}` - Signal was successfully enqueued
  - `{:error, :queue_overflow}` - Queue is at max capacity

  ## Examples

      iex> state = %Runtime.State{pending: :queue.new(), max_queue_size: 2}
      iex> Runtime.State.enqueue_signal(state, %Signal{type: "test"})
      {:ok, %Runtime.State{pending: updated_queue}}

      iex> state = %Runtime.State{pending: full_queue, max_queue_size: 1}
      iex> Runtime.State.enqueue_signal(state, %Signal{type: "test"})
      {:error, :queue_overflow}
  """
  @spec enqueue(%__MODULE__{}, Signal.t()) :: {:ok, %__MODULE__{}} | {:error, :queue_overflow}
  def enqueue(%__MODULE__{} = state, %Signal{} = signal) do
    queue_size = :queue.len(state.pending)

    if queue_size >= state.max_queue_size do
      debug(
        "Queue overflow, dropping signal",
        queue_size: queue_size,
        max_size: state.max_queue_size
      )

      PubSub.emit(state, RuntimeSignal.queue_overflow(), %{
        queue_size: queue_size,
        max_size: state.max_queue_size
      })

      {:error, :queue_overflow}
    else
      {:ok, %{state | pending: :queue.in(signal, state.pending)}}
    end
  end

  @doc """
  Dequeues a signal from the state's pending queue.

  Returns the next signal and updated state with the signal removed from the queue.
  Returns error if queue is empty.

  ## Parameters

  - `state` - Current runtime state

  ## Returns

  - `{:ok, signal, new_state}` - Signal was successfully dequeued
  - `{:error, :empty_queue}` - Queue is empty

  ## Examples

      iex> state = %Runtime.State{pending: queue_with_items}
      iex> Runtime.State.dequeue(state)
      {:ok, %Signal{type: "test"}, %Runtime.State{pending: updated_queue}}

      iex> state = %Runtime.State{pending: :queue.new()}
      iex> Runtime.State.dequeue(state)
      {:error, :empty_queue}
  """
  @spec dequeue(%__MODULE__{}) :: {:ok, term(), %__MODULE__{}} | {:error, :empty_queue}
  def dequeue(%__MODULE__{} = state) do
    case :queue.out(state.pending) do
      {{:value, signal}, new_queue} ->
        {:ok, signal, %{state | pending: new_queue}}

      {:empty, _} ->
        {:error, :empty_queue}
    end
  end

  @doc """
  Empties the pending queue in the runtime state.

  Returns a new state with an empty queue.

  ## Parameters

  - `state` - Current runtime state

  ## Returns

  - `{:ok, new_state}` - Queue was successfully emptied

  ## Examples

      iex> state = %Runtime.State{pending: queue_with_items}
      iex> Runtime.State.clear_queue(state)
      {:ok, %Runtime.State{pending: :queue.new()}}
  """
  @spec clear_queue(%__MODULE__{}) :: {:ok, %__MODULE__{}}
  def clear_queue(%__MODULE__{} = state) do
    PubSub.emit(state, RuntimeSignal.queue_cleared(), %{queue_size: :queue.len(state.pending)})
    {:ok, %{state | pending: :queue.new()}}
  end

  def validate_state(%__MODULE__{pubsub: nil}), do: {:error, "PubSub module is required"}
  def validate_state(%__MODULE__{agent: nil}), do: {:error, "Agent is required"}
  def validate_state(_state), do: :ok
end
