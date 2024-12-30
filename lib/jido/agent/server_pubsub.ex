defmodule Jido.Agent.Server.PubSub do
  @moduledoc false
  # Handles PubSub event management for Jido Agent Servers.

  # This module provides functionality for:
  # - Event emission
  # - Topic management
  # - Event subscription
  # - Signal generation
  # - Signal processing

  # All events are broadcast through Phoenix.PubSub and follow a consistent
  # format using Jido.Signal structs.

  # ## Examples

  #     iex> state = %Jido.Agent.Server.State{pubsub: MyPubSub, topic: "jido.agent.agent-123"}
  #     iex> Jido.Agent.Server.PubSub.subscribe(state)
  #     :ok

  use ExDbug, enabled: false

  alias Jido.Signal
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal

  @default_topic_prefix "jido.agent"

  @doc """
  Subscribes the current process to an agent's topic and tracks subscription in state.

  ## Parameters
    - state: The Server state containing PubSub configuration

  ## Returns
    - {:ok, new_state} on successful subscription with updated subscriptions
    - {:error, reason} on failure

  ## Examples

      iex> state = %Jido.Agent.Server.State{pubsub: MyPubSub, topic: "jido.agent.agent-123"}
      iex> Jido.Agent.Server.PubSub.subscribe(state)
      {:ok, %Jido.Agent.Server.State{subscriptions: ["jido.agent.agent-123"]}}
  """
  @spec subscribe(ServerState.t(), String.t()) :: {:ok, ServerState.t()} | {:error, term()}
  def subscribe(%ServerState{pubsub: nil} = state, _topic), do: {:ok, state}

  def subscribe(%ServerState{pubsub: pubsub, subscriptions: subscriptions} = state, topic) do
    if topic in subscriptions do
      {:ok, state}
    else
      dbug("Subscribing to topic", pubsub: pubsub, topic: topic)

      case Phoenix.PubSub.subscribe(pubsub, topic) do
        :ok ->
          new_state = %{state | subscriptions: [topic | subscriptions]}
          {:ok, new_state}

        error ->
          error
      end
    end
  end

  @doc """
  Unsubscribes the current process from an agent's topic and removes from tracked subscriptions.

  ## Parameters
    - state: The Server state containing PubSub configuration

  ## Returns
    - {:ok, new_state} on successful unsubscription with updated subscriptions
    - {:error, reason} on failure

  ## Examples

      iex> state = %Jido.Agent.Server.State{pubsub: MyPubSub, topic: "jido.agent.agent-123", subscriptions: ["jido.agent.agent-123"]}
      iex> Jido.Agent.Server.PubSub.unsubscribe(state, "jido.agent.agent-123")
      {:ok, %Jido.Agent.Server.State{subscriptions: []}}
  """
  @spec unsubscribe(ServerState.t(), String.t()) :: {:ok, ServerState.t()} | {:error, term()}
  def unsubscribe(%ServerState{pubsub: nil} = state, _topic), do: {:ok, state}

  def unsubscribe(%ServerState{pubsub: pubsub} = state, topic) do
    dbug("Unsubscribing from topic", pubsub: pubsub, topic: topic)

    case Phoenix.PubSub.unsubscribe(pubsub, topic) do
      :ok ->
        new_state = %{state | subscriptions: List.delete(state.subscriptions, topic)}
        {:ok, new_state}

      error ->
        error
    end
  end

  @doc """
  Emits an event to the agent's topic.

  ## Parameters
    - state: The Server state
    - event_type: The type of event to emit
    - payload: The event payload

  ## Returns
    - :ok on successful emission
    - {:error, reason} on failure

  ## Examples

      iex> state = %Jido.Agent.Server.State{pubsub: MyPubSub, topic: "jido.agent.agent-123"}
      iex> Jido.Agent.Server.PubSub.emit(state, :started, %{agent_id: "agent-123"})
      :ok
  """
  @spec emit_event(ServerState.t(), atom(), map()) :: :ok | {:error, term()}
  def emit_event(%ServerState{pubsub: nil} = state), do: {:ok, state}

  def emit_event(%ServerState{} = state, event_type, payload) do
    dbug("Emitting event", type: event_type, payload: payload)

    with {:ok, signal} <- ServerSignal.event_signal(state, event_type, payload),
         :ok <- broadcast(state, signal) do
      :ok
    else
      {:error, reason} ->
        dbug("Failed to emit event", reason: reason)
        {:error, reason}
    end
  end

  @doc """
  Generates a full topic string for an agent ID.

  ## Parameters
    - agent_id: The unique identifier for the agent

  ## Returns
    - String topic in format "jido.agent.{agent_id}"

  ## Examples

      iex> Jido.Agent.Server.PubSub.generate_topic("agent-123")
      "jido.agent.agent-123"
  """
  @spec generate_topic(String.t(), String.t()) :: String.t()
  def generate_topic(agent_id, prefix \\ @default_topic_prefix), do: "#{prefix}.#{agent_id}"

  @spec broadcast(ServerState.t(), Signal.t()) :: :ok | {:error, term()}
  defp broadcast(%ServerState{pubsub: pubsub, topic: topic}, signal) do
    dbug("Broadcasting signal", topic: topic, signal: signal)
    Phoenix.PubSub.broadcast(pubsub, topic, signal)
  end
end
