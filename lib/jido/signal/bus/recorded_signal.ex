defmodule Jido.Signal.Bus.RecordedSignal do
  @moduledoc """
  RecordedSignal represents a signal that has been recorded in the bus's log.
  It includes:
  - id: A unique identifier for this recorded signal
  - correlation_id: The ID of the signal that caused this signal (if any)
  - created_at: Timestamp for ordering
  - type: The signal's type (used for routing)
  - signal: The original signal in its entirety
  """
  use TypedStruct
  alias Jido.Signal
  alias Jido.Signal.ID

  @type uuid :: String.t()

  typedstruct do
    field(:id, uuid())
    field(:correlation_id, uuid())
    field(:created_at, DateTime.t())
    field(:type, String.t())
    field(:signal, Signal.t())
  end

  @doc """
  Creates a new RecordedSignal from an original signal.
  The type is extracted from the signal and stored at the top level for easy access.
  """
  def from_signal(signal) do
    {uuid, timestamp} = ID.generate()

    %__MODULE__{
      id: uuid,
      correlation_id: Map.get(signal, :id),
      created_at: timestamp,
      type: signal.type,
      signal: signal
    }
  end

  @doc """
  Creates multiple RecordedSignals from a list of signals, ensuring sequential ordering.
  """
  def from_signals(signals) when is_list(signals) do
    # Get batch of sequential UUIDs
    {uuids, timestamp} = ID.generate_batch(length(signals))

    # Create signals with sequential IDs
    signals
    |> Enum.zip(uuids)
    |> Enum.map(fn {signal, uuid} ->
      %__MODULE__{
        id: uuid,
        correlation_id: Map.get(signal, :id),
        created_at: DateTime.from_unix!(timestamp, :millisecond),
        type: signal.type,
        signal: signal
      }
    end)
  end

  # alias Jido.Bus.RecordedSignal

  # @type causation_id :: uuid() | nil
  # @type correlation_id :: uuid() | nil
  # @type created_at :: DateTime.t()
  # @type data :: domain_signal()
  # @type domain_signal :: struct()
  # @type signal_id :: uuid()
  # @type signal_number :: non_neg_integer()
  # @type type :: String.t()
  # @type jido_metadata :: map()
  # @type stream_id :: String.t()
  # @type stream_version :: non_neg_integer()
  # @type uuid :: String.t()
  # @type signal :: struct()

  # @type t :: %RecordedSignal{
  #         signal_id: signal_id(),
  #         signal_number: signal_number(),
  #         stream_id: stream_id(),
  #         stream_version: stream_version(),
  #         causation_id: causation_id(),
  #         correlation_id: correlation_id(),
  #         type: type(),
  #         data: data(),
  #         jido_metadata: jido_metadata(),
  #         created_at: created_at()
  #       }

  # @type enriched_metadata :: %{
  #         :signal_id => signal_id(),
  #         :signal_number => signal_number(),
  #         :stream_id => stream_id(),
  #         :stream_version => stream_version(),
  #         :correlation_id => correlation_id(),
  #         :causation_id => causation_id(),
  #         :created_at => created_at(),
  #         optional(atom()) => term(),
  #         optional(String.t()) => term()
  #       }

  # defstruct [
  #   :signal_id,
  #   :signal_number,
  #   :stream_id,
  #   :stream_version,
  #   :causation_id,
  #   :correlation_id,
  #   :type,
  #   :data,
  #   :created_at,
  #   jido_metadata: %{}
  # ]

  # @doc """
  # Enrich the signal's metadata with fields from the `RecordedSignal` struct and
  # any additional metadata passed as an option.
  # """
  # @spec enrich_metadata(t(), [{:additional_metadata, map()}]) :: enriched_metadata()
  # def enrich_metadata(%RecordedSignal{} = signal, opts) do
  #   %RecordedSignal{
  #     signal_id: signal_id,
  #     signal_number: signal_number,
  #     stream_id: stream_id,
  #     stream_version: stream_version,
  #     correlation_id: correlation_id,
  #     causation_id: causation_id,
  #     created_at: created_at,
  #     jido_metadata: jido_metadata
  #   } = signal

  #   additional_metadata = Keyword.get(opts, :additional_metadata, %{})

  #   %{
  #     signal_id: signal_id,
  #     signal_number: signal_number,
  #     stream_id: stream_id,
  #     stream_version: stream_version,
  #     correlation_id: correlation_id,
  #     causation_id: causation_id,
  #     created_at: created_at
  #   }
  #   |> Map.merge(jido_metadata || %{})
  #   |> Map.merge(additional_metadata)
  # end

  # @doc """
  # Map a list of `Jido.Bus.RecordedSignal` structs to their signal data.
  # """
  # @spec map_from_recorded_signals(list(RecordedSignal.t())) :: [signal]
  # def map_from_recorded_signals(recorded_signals) when is_list(recorded_signals) do
  #   Enum.map(recorded_signals, &map_from_recorded_signal/1)
  # end

  # @doc """
  # Map an `Jido.Bus.RecordedSignal` struct to its signal data.
  # """
  # @spec map_from_recorded_signal(RecordedSignal.t()) :: signal
  # def map_from_recorded_signal(%RecordedSignal{data: data}), do: data
end
