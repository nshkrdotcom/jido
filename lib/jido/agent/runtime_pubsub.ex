defmodule Jido.Agent.Runtime.PubSub do
  @moduledoc """
  Handles PubSub event management for Jido Agent Runtimes.

  This module provides functionality for:
  - Event emission
  - Topic management
  - Event subscription
  - Signal generation
  - Signal processing

  All events are broadcast through Phoenix.PubSub and follow a consistent
  format using Jido.Signal structs.
  """

  use Jido.Util, debug_enabled: false
  alias Jido.Signal
  alias Jido.Agent.Runtime.State, as: RuntimeState
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  require Logger

  @doc """
  Subscribes the current process to an agent's topic.

  ## Parameters
    - state: The Runtime state containing PubSub configuration

  ## Returns
    - :ok on successful subscription
    - {:error, reason} on failure
  """
  @spec subscribe(RuntimeState.t()) :: :ok | {:error, term()}
  def subscribe(%RuntimeState{pubsub: pubsub, topic: topic}) do
    debug("Subscribing to topic", pubsub: pubsub, topic: topic)
    Phoenix.PubSub.subscribe(pubsub, topic)
  end

  @doc """
  Unsubscribes the current process from an agent's topic.

  ## Parameters
    - state: The Runtime state containing PubSub configuration

  ## Returns
    - :ok on successful unsubscription
    - {:error, reason} on failure
  """
  @spec unsubscribe(RuntimeState.t()) :: :ok | {:error, term()}
  def unsubscribe(%RuntimeState{pubsub: pubsub, topic: topic}) do
    debug("Unsubscribing from topic", pubsub: pubsub, topic: topic)
    Phoenix.PubSub.unsubscribe(pubsub, topic)
  end

  @doc """
  Emits an event to the agent's topic.

  ## Parameters
    - state: The Runtime state
    - event_type: The type of event to emit
    - payload: The event payload

  ## Returns
    - {:ok, state} on successful emission
    - {:error, reason} on failure

  ## Examples

      PubSub.emit(state, :started, %{agent_id: "agent-123"})
      PubSub.emit(state, :state_changed, %{from: :idle, to: :running})
  """
  @spec emit(RuntimeState.t(), atom(), map()) :: :ok | {:error, term()}
  def emit(%RuntimeState{} = state, event_type, payload) do
    debug("Emitting event", type: event_type, payload: payload)

    with signal <- RuntimeSignal.event_to_signal(state, event_type, payload),
         :ok <- broadcast(state, signal) do
      :ok
    end
  end

  @doc """
  Generates a full topic string for an agent ID.

  ## Parameters
    - agent_id: The unique identifier for the agent

  ## Returns
    - String topic in format "jido.agent.{agent_id}"

  ## Examples

      iex> PubSub.generate_topic("agent-123")
      "jido.agent.agent-123"
  """
  @spec generate_topic(String.t()) :: String.t()
  def generate_topic(agent_id), do: "jido.agent.#{agent_id}"

  @spec broadcast(RuntimeState.t(), Signal.t()) :: :ok | {:error, term()}
  defp broadcast(%RuntimeState{pubsub: pubsub, topic: topic}, signal) do
    debug("Broadcasting signal", topic: topic, signal: signal)
    Phoenix.PubSub.broadcast(pubsub, topic, signal)
  end
end
