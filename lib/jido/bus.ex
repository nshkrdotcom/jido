defmodule Jido.Bus do
  @moduledoc """
  Use the signal store configured for a Commanded application.

  ### Telemetry Signals

  Adds telemetry signals for the following functions. Signals are emitted in the form

  `[:jido, :bus, signal]` with their spannable postfixes (`start`, `stop`, `exception`)

    * ack/3
    * adapter/2
    * publish/4
    * delete_snapshot/2
    * unsubscribe/3
    * read_snapshot/2
    * record_snapshot/2
    * replay/2
    * replay/3
    * replay/4
    * subscribe/2
    * subscribe_persistent/5
    * subscribe_persistent/6
    * unsubscribe/2

  """
  alias Commanded.Application
  alias Commanded.Signal.Upcast

  use TypedStruct

  typedstruct do
    field(:id, String.t(), default: UUID.uuid4())
    field(:adapter, module(), enforce: true)
    field(:config, Keyword.t(), default: [])
  end

  @type application :: Application.t()
  @type config :: Keyword.t()

  @doc """
  Append one or more signals to a stream atomically.
  """
  def publish(bus, stream_id, expected_version, signals, opts \\ []) do
    meta = %{
      bus: bus,
      stream_id: stream_id,
      expected_version: expected_version
    }

    span(:publish, meta, fn ->
      if function_exported?(bus.adapter, :publish, 5) do
        bus.adapter.publish(bus, stream_id, expected_version, signals, opts)
      else
        bus.adapter.publish(
          bus,
          stream_id,
          expected_version,
          signals
        )
      end
    end)
  end

  @doc """
  Streams signals from the given stream, in the order in which they were originally written.
  """
  def replay(bus, stream_id, start_version \\ 0, read_batch_size \\ 1_000) do
    meta = %{
      bus: bus,
      stream_id: stream_id,
      start_version: start_version,
      read_batch_size: read_batch_size
    }

    span(:replay, meta, fn ->
      case bus.adapter.replay(
             bus,
             stream_id,
             start_version,
             read_batch_size
           ) do
        {:error, _error} = error ->
          error

        stream ->
          stream
          # stream ->
          #   Upcast.upcast_signal_stream(stream, additional_metadata: %{application: application})
      end
    end)
  end

  @doc """
  Create a transient subscription to a single signal stream.

  The signal store will publish any signals appended to the given stream to the
  `subscriber` process as an `{:signals, signals}` message.

  The subscriber does not need to acknowledge receipt of the signals.
  """
  def subscribe(bus, stream_id) do
    span(:subscribe, %{bus: bus, stream_id: stream_id}, fn ->
      bus.adapter.subscribe(bus, stream_id)
    end)
  end

  @doc """
  Create a persistent subscription to an signal stream.

  To subscribe to all signals appended to any stream use `:all` as the stream
  when subscribing.

  The signal store will remember the subscribers last acknowledged signal.
  Restarting the named subscription will resume from the next signal following
  the last seen.

  Once subscribed, the subscriber process should be sent a
  `{:subscribed, subscription}` message to allow it to defer initialisation
  until the subscription has started.

  The subscriber process will be sent all signals persisted to the stream. It
  will receive a `{:signals, signals}` message for each batch of signals persisted
  for a single aggregate.

  The subscriber must ack each received, and successfully processed signal, using
  `Jido.Bus.ack/3`.

  ## Examples

  Subscribe to all streams:

      {:ok, subscription} =
        Jido.Bus.subscribe_persistent(MyApp, :all, "Example", self(), :current)

  Subscribe to a single stream:

      {:ok, subscription} =
        Jido.Bus.subscribe_persistent(MyApp, "stream1", "Example", self(), :origin)

  """
  def subscribe_persistent(
        bus,
        stream_id,
        subscription_name,
        subscriber,
        start_from,
        opts \\ []
      ) do
    meta = %{
      bus: bus,
      stream_id: stream_id,
      subscription_name: subscription_name,
      subscriber: subscriber,
      start_from: start_from
    }

    span(:subscribe_persistent, meta, fn ->
      if function_exported?(bus.adapter, :subscribe_persistent, 6) do
        bus.adapter.subscribe_persistent(
          bus,
          stream_id,
          subscription_name,
          subscriber,
          start_from,
          opts
        )
      else
        bus.adapter.subscribe_persistent(
          bus,
          stream_id,
          subscription_name,
          subscriber,
          start_from
        )
      end
    end)
  end

  @doc """
  Acknowledge receipt and successful processing of the given signal received from
  a subscription to an signal stream.
  """
  def ack(bus, subscription, signal) do
    meta = %{bus: bus, subscription: subscription, signal: signal}

    span(:ack, meta, fn ->
      bus.adapter.ack(bus, subscription, signal)
    end)
  end

  @doc """
  Unsubscribe an existing subscriber from signal notifications.

  This will not delete the subscription.

  ## Example

      :ok = Jido.Bus.unsubscribe(MyApp, subscription)

  """
  def unsubscribe(bus, subscription) do
    span(:unsubscribe, %{bus: bus, subscription: subscription}, fn ->
      bus.adapter.unsubscribe(bus, subscription)
    end)
  end

  @doc """
  Delete an existing subscription.

  ## Example

      :ok = Jido.Bus.unsubscribe(MyApp, :all, "Example")

  """
  def unsubscribe(bus, subscribe_persistent, handler_name) do
    meta = %{
      bus: bus,
      subscribe_persistent: subscribe_persistent,
      handler_name: handler_name
    }

    span(:unsubscribe, meta, fn ->
      bus.adapter.unsubscribe(bus, subscribe_persistent, handler_name)
    end)
  end

  @doc """
  Read a snapshot, if available, for a given source.
  """
  def read_snapshot(bus, source_id) do
    span(:read_snapshot, %{bus: bus, source_id: source_id}, fn ->
      bus.adapter.read_snapshot(bus, source_id)
    end)
  end

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  def record_snapshot(bus, snapshot) do
    span(:record_snapshot, %{bus: bus, snapshot: snapshot}, fn ->
      bus.adapter.record_snapshot(bus, snapshot)
    end)
  end

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  def delete_snapshot(bus, source_id) do
    span(:delete_snapshot, %{bus: bus, source_id: source_id}, fn ->
      bus.adapter.delete_snapshot(bus, source_id)
    end)
  end

  defp span(signal, meta, func) do
    :telemetry.span([:jido, :bus, signal], meta, fn ->
      {func.(), meta}
    end)
  end
end
