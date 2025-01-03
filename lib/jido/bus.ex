defmodule Jido.Bus do
  @moduledoc """
  A simple message bus implementation for Jido.
  """
  use TypedStruct

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:adapter, module(), enforce: true)
    field(:config, Keyword.t(), default: [])
  end

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

  def subscribe(bus, stream_id) do
    meta = build_meta(bus, stream_id)

    span(:subscribe, meta, fn ->
      bus.adapter.subscribe(bus, stream_id)
    end)
  end

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

  def ack(bus, pid, recorded_signal) do
    meta = build_meta(bus, nil, pid: pid, recorded_signal: recorded_signal)

    span(:ack, meta, fn ->
      bus.adapter.ack(bus, pid, recorded_signal)
    end)
  end

  def unsubscribe(bus, subscription) do
    meta = build_meta(bus, nil, subscription: subscription)

    span(:unsubscribe, meta, fn ->
      bus.adapter.unsubscribe(bus, subscription)
    end)
  end

  def read_snapshot(bus, source_id) do
    meta = build_meta(bus, nil, source_id: source_id)

    span(:read_snapshot, meta, fn ->
      bus.adapter.read_snapshot(bus, source_id)
    end)
  end

  def record_snapshot(bus, snapshot) do
    meta = build_meta(bus, nil, snapshot: snapshot)

    span(:record_snapshot, meta, fn ->
      bus.adapter.record_snapshot(bus, snapshot)
    end)
  end

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
