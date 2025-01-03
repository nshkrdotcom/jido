defmodule Jido.Bus.Adapters.PubSub do
  @moduledoc """
  A Jido Bus adapter implementation using Phoenix.PubSub
  """
  @behaviour Jido.Bus.Adapter

  alias Phoenix.PubSub
  alias Jido.Bus

  @impl true
  def child_spec(context, opts) do
    name = Keyword.get(opts, :name, context)
    pubsub_name = Module.concat(name, PubSub)

    children = [
      {Phoenix.PubSub, name: pubsub_name}
    ]

    bus = %Bus{
      id: Atom.to_string(name),
      adapter: __MODULE__,
      config: [pubsub_name: pubsub_name]
    }

    {:ok, children, bus}
  end

  @impl true
  def publish(bus, stream_id, _expected_version, signals, _opts) do
    pubsub_name = get_pubsub_name(bus)

    Enum.each(signals, fn signal ->
      PubSub.broadcast(pubsub_name, stream_id, {:signal, signal})
    end)

    :ok
  end

  @impl true
  def replay(_bus, _stream_id, _start_version, _batch_size) do
    {:error, :not_implemented}
  end

  @impl true
  def subscribe(bus, stream_id) do
    pubsub_name = get_pubsub_name(bus)
    PubSub.subscribe(pubsub_name, stream_id)
  end

  @impl true
  def subscribe_persistent(_bus, _stream_id, _subscription_name, _subscriber, _start_from, _opts) do
    {:error, :not_implemented}
  end

  @impl true
  def ack(_bus, _pid, _recorded_signal) do
    {:error, :not_implemented}
  end

  @impl true
  def unsubscribe(bus, subscription) when is_pid(subscription) do
    pubsub_name = get_pubsub_name(bus)
    PubSub.unsubscribe(pubsub_name, subscription)
  end

  @impl true
  def read_snapshot(_bus, _source_id) do
    {:error, :not_implemented}
  end

  @impl true
  def record_snapshot(_bus, _snapshot) do
    {:error, :not_implemented}
  end

  @impl true
  def delete_snapshot(_bus, _source_id) do
    {:error, :not_implemented}
  end

  # Private helpers

  defp get_pubsub_name(bus) do
    Keyword.fetch!(bus.config, :pubsub_name)
  end
end
