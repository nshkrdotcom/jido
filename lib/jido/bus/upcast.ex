defmodule Commanded.Signal.Upcast do
  @moduledoc false

  alias Commanded.Signal.Upcaster
  alias Jido.Bus.RecordedSignal

  def upcast_signal_stream(signal_stream, opts \\ [])

  def upcast_signal_stream(%Stream{} = signal_stream, opts),
    do: Stream.map(signal_stream, &upcast_signal(&1, opts))

  def upcast_signal_stream(signal_stream, opts),
    do: Enum.map(signal_stream, &upcast_signal(&1, opts))

  def upcast_signal(%RecordedSignal{} = signal, opts) do
    %RecordedSignal{data: data} = signal

    enriched_metadata = RecordedSignal.enrich_metadata(signal, opts)

    %RecordedSignal{signal | data: Upcaster.upcast(data, enriched_metadata)}
  end
end
