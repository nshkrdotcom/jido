defmodule Jido.Agent.Adapter.PubSub do
  @moduledoc """
  Phoenix.PubSub adapter implementing the Communication port.
  """
  @behaviour Jido.Agent.Port.Communication

  alias Phoenix.PubSub

  @impl true
  def init(pubsub) when is_atom(pubsub), do: {:ok, pubsub}
  def init(_), do: {:error, "Invalid PubSub configuration"}

  @impl true
  def broadcast_event(pubsub, topic, payload) do
    PubSub.broadcast(pubsub, topic, payload)
  end

  @impl true
  def subscribe(pubsub, topic) do
    PubSub.subscribe(pubsub, topic)
  end

  @impl true
  def unsubscribe(pubsub, topic) do
    PubSub.unsubscribe(pubsub, topic)
  end
end
