defmodule JidoTest.Helpers.SignalFactory do
  @moduledoc false
  alias Jido.Bus.RecordedSignal
  alias Jido.Signal

  def map_to_recorded_signals(signals, initial_signal_number \\ 1, opts \\ []) do
    stream_id = Jido.Util.generate_id()
    causation_id = Keyword.get(opts, :causation_id, Jido.Util.generate_id())
    correlation_id = Keyword.get(opts, :correlation_id, Jido.Util.generate_id())
    jido_metadata = Keyword.get(opts, :jido_metadata, %{})

    fields = [
      causation_id: causation_id,
      correlation_id: correlation_id,
      jido_metadata: jido_metadata
    ]

    signals
    |> Signal.map_to_signal_data(fields)
    |> Enum.with_index(initial_signal_number)
    |> Enum.map(fn {signal, index} ->
      %RecordedSignal{
        signal_id: Jido.Util.generate_id(),
        signal_number: index,
        stream_id: stream_id,
        stream_version: index,
        causation_id: signal.source,
        correlation_id: signal.id,
        type: signal.type,
        data: signal.data,
        jido_metadata: signal.jido_metadata,
        created_at: DateTime.utc_now()
      }
    end)
  end
end
