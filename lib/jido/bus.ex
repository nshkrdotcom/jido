defmodule Jido.Bus do
  @moduledoc """
  A simple message bus implementation for Jido.

  The Bus module provides a high-level interface for publishing, subscribing to, and replaying signals
  (events/commands) through a message bus. It delegates the actual implementation to an adapter module
  while providing consistent telemetry instrumentation.

  ## Features

  - Publish signals to streams
  - Subscribe to streams (persistent and transient)
  - Replay signals from a stream
  - Snapshot management
  - Built-in telemetry instrumentation
  - Pluggable adapter architecture supporting:
    - Ephemeral adapters (Phoenix.PubSub) for in-memory pub/sub
    - Durable adapters (EventStore) for persistent event storage
    - In-memory durable adapter for testing and development

  ## Adapters

  The bus supports two main types of adapters:

  ### Ephemeral Adapters
  - Phoenix.PubSub based adapter for in-memory pub/sub
  - No persistence, messages are lost on restart
  - Ideal for transient subscriptions and real-time updates

  ### Durable Adapters
  - EventStore adapter for persistent event storage
  - In-memory durable adapter for testing/development
  - Full event history and replay capabilities
  - Support for persistent subscriptions

  ## Usage

  ```elixir
  # Create a bus with ephemeral PubSub adapter
  bus = %Jido.Bus{
    id: "pubsub_bus",
    adapter: Jido.Bus.Adapters.PubSub,
    config: [pubsub: MyApp.PubSub]
  }

  # Create a bus with durable InMemory adapter
  bus = %Jido.Bus{
    id: "event_bus",
    adapter: Jido.Bus.Adapters.DurableInMemory,
    config: [event_store: MyApp.EventStore]
  }

  # Publish signals
  {:ok, _} = Jido.Bus.publish(bus, "stream-123", 0, [signal1, signal2])

  # Subscribe to a stream
  {:ok, subscription} = Jido.Bus.subscribe(bus, "stream-123")

  # Create persistent subscription (durable adapters only)
  {:ok, _} = Jido.Bus.subscribe_persistent(bus, "stream-123", "my-sub", self(), :origin)
  ```
  """
  use TypedStruct

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:adapter, module(), enforce: true)
    field(:config, Keyword.t(), default: [])
  end

  @doc """
  Publishes signals to a stream.

  ## Parameters

  - `bus` - The bus instance
  - `stream_id` - The target stream identifier
  - `expected_version` - Expected version of the stream (for optimistic concurrency)
  - `signals` - List of signals to publish
  - `opts` - Optional parameters passed to the adapter

  ## Returns

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  """
  def publish(bus, stream_id, expected_version, signals, opts \\ []) do
    meta =
      build_meta(bus, stream_id,
        expected_version: expected_version,
        signals: signals,
        opts: opts
      )

    span(:publish, meta, fn ->
      bus.adapter.publish(bus, stream_id, expected_version, signals, opts)
    end)
  end

  @doc """
  Replays signals from a stream starting at a specific version.

  ## Parameters

  - `bus` - The bus instance
  - `stream_id` - The stream to replay from
  - `start_version` - Version to start replaying from
  - `batch_size` - Number of signals to read per batch

  ## Returns

  Returns `{:ok, signals}` on success or `{:error, reason}` on failure.
  """
  def replay(bus, stream_id, start_version, batch_size) do
    meta =
      build_meta(bus, stream_id,
        start_version: start_version,
        batch_size: batch_size
      )

    span(:replay, meta, fn ->
      bus.adapter.replay(bus, stream_id, start_version, batch_size)
    end)
  end

  @doc """
  Creates a transient subscription to a stream.

  ## Parameters

  - `bus` - The bus instance
  - `stream_id` - The stream to subscribe to

  ## Returns

  Returns `{:ok, subscription}` on success or `{:error, reason}` on failure.
  """
  def subscribe(bus, stream_id) do
    meta = build_meta(bus, stream_id)

    span(:subscribe, meta, fn ->
      bus.adapter.subscribe(bus, stream_id)
    end)
  end

  @doc """
  Creates a persistent subscription to a stream.

  ## Parameters

  - `bus` - The bus instance
  - `stream_id` - The stream to subscribe to
  - `subscription_name` - Unique name for the subscription
  - `subscriber` - PID of the subscriber process
  - `start_from` - Starting position (:origin, :current, or version number)
  - `opts` - Optional parameters passed to the adapter

  ## Returns

  Returns `{:ok, subscription}` on success or `{:error, reason}` on failure.
  """
  def subscribe_persistent(bus, stream_id, subscription_name, subscriber, start_from, opts \\ []) do
    meta =
      build_meta(bus, stream_id,
        subscription_name: subscription_name,
        subscriber: subscriber,
        start_from: start_from,
        opts: opts
      )

    span(:subscribe_persistent, meta, fn ->
      bus.adapter.subscribe_persistent(
        bus,
        stream_id,
        subscription_name,
        subscriber,
        start_from,
        opts
      )
    end)
  end

  @doc """
  Acknowledges processing of a signal by a subscriber.

  ## Parameters

  - `bus` - The bus instance
  - `pid` - PID of the subscriber
  - `recorded_signal` - The signal being acknowledged

  ## Returns

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def ack(bus, pid, recorded_signal) do
    meta = build_meta(bus, nil, pid: pid, recorded_signal: recorded_signal)

    span(:ack, meta, fn ->
      bus.adapter.ack(bus, pid, recorded_signal)
    end)
  end

  @doc """
  Removes a subscription.

  ## Parameters

  - `bus` - The bus instance
  - `subscription` - The subscription to remove

  ## Returns

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def unsubscribe(bus, subscription) do
    meta = build_meta(bus, nil, subscription: subscription)

    span(:unsubscribe, meta, fn ->
      bus.adapter.unsubscribe(bus, subscription)
    end)
  end

  @doc """
  Reads the latest snapshot for a source.

  ## Parameters

  - `bus` - The bus instance
  - `source_id` - ID of the source to read snapshot for

  ## Returns

  Returns `{:ok, snapshot}` if found, `{:error, :not_found}` if no snapshot exists,
  or `{:error, reason}` on other failures.
  """
  def read_snapshot(bus, source_id) do
    meta = build_meta(bus, nil, source_id: source_id)

    span(:read_snapshot, meta, fn ->
      bus.adapter.read_snapshot(bus, source_id)
    end)
  end

  @doc """
  Records a new snapshot for a source.

  ## Parameters

  - `bus` - The bus instance
  - `snapshot` - The snapshot to record

  ## Returns

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def record_snapshot(bus, snapshot) do
    meta = build_meta(bus, nil, snapshot: snapshot)

    span(:record_snapshot, meta, fn ->
      bus.adapter.record_snapshot(bus, snapshot)
    end)
  end

  @doc """
  Deletes the snapshot for a source.

  ## Parameters

  - `bus` - The bus instance
  - `source_id` - ID of the source whose snapshot should be deleted

  ## Returns

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def delete_snapshot(bus, source_id) do
    meta = build_meta(bus, nil, source_id: source_id)

    span(:delete_snapshot, meta, fn ->
      bus.adapter.delete_snapshot(bus, source_id)
    end)
  end

  defp build_meta(bus, stream_id, opts \\ []) do
    Map.new(opts)
    |> Map.merge(%{
      bus: bus,
      stream_id: stream_id
    })
  end

  defp span(event, meta, func) do
    :telemetry.span([:jido, :bus, event], meta, fn ->
      {func.(), meta}
    end)
  end
end
