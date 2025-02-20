defmodule Jido.Bus.RecordedSignalTest do
  use ExUnit.Case

  alias Jido.Bus.RecordedSignal
  alias Jido.Signal

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  setup do
    [signal] =
      map_to_recorded_signals(
        [
          %BankAccountOpened{account_number: "123", initial_balance: 1_000}
        ],
        1,
        jido_metadata: %{"key1" => "value1", "key2" => "value2"}
      )

    [signal: signal]
  end

  describe "RecordedSignal struct" do
    test "enrich_metadata/2 should add a number of fields to the metadata", %{signal: signal} do
      %RecordedSignal{
        signal_id: signal_id,
        signal_number: signal_number,
        stream_id: stream_id,
        stream_version: stream_version,
        correlation_id: correlation_id,
        causation_id: causation_id,
        created_at: created_at
      } = signal

      enriched_metadata =
        RecordedSignal.enrich_metadata(signal,
          additional_metadata: %{
            application: ExampleApplication
          }
        )

      assert enriched_metadata == %{
               # Signal string-keyed metadata
               "key1" => "value1",
               "key2" => "value2",
               # Standard signal fields
               signal_id: signal_id,
               signal_number: signal_number,
               stream_id: stream_id,
               stream_version: stream_version,
               correlation_id: correlation_id,
               causation_id: causation_id,
               created_at: created_at,
               # Additional field
               application: ExampleApplication
             }
    end

    test "map_from_recorded_signal/1 extracts the data from a recorded signal", %{signal: signal} do
      expected_data = %BankAccountOpened{account_number: "123", initial_balance: 1_000}
      assert RecordedSignal.map_from_recorded_signal(signal) == expected_data
    end
  end

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
