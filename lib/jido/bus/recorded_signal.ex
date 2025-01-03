defmodule Jido.Bus.RecordedSignal do
  @moduledoc """
  Contains the persisted stream identity and signal data for a single signal.

  Signals are immutable once recorded.

  ## Recorded signal fields

    - `signal_id` - a globally unique UUID to identify the signal
    - `signal_number` - a globally unique, monotonically incrementing and gapless integer
    - `stream_id` - the stream identity for the signal
    - `stream_version` - the version of the stream for the signal
    - `causation_id` - an optional UUID identifier used to identify which message you are responding to
    - `correlation_id` - an optional UUID identifier used to correlate related messages
    - `data` - the signal data deserialized into a struct
    - `metadata` - a string keyed map of metadata associated with the signal
    - `created_at` - the datetime, in UTC, indicating when the signal was created
  """

  use TypedStruct
  alias __MODULE__

  @type signal_id :: String.t()
  @type signal_number :: non_neg_integer()
  @type stream_id :: String.t()
  @type stream_version :: non_neg_integer()
  @type causation_id :: String.t() | nil
  @type correlation_id :: String.t() | nil
  @type signal_type :: String.t()
  @type data :: struct()
  @type metadata :: map()
  @type created_at :: DateTime.t()

  @type enriched_metadata :: %{
          :signal_id => signal_id(),
          :signal_number => signal_number(),
          :stream_id => stream_id(),
          :stream_version => stream_version(),
          :correlation_id => correlation_id(),
          :causation_id => causation_id(),
          :created_at => created_at(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  typedstruct do
    field(:signal_id, signal_id(), enforce: true)
    field(:signal_number, signal_number(), enforce: true)
    field(:stream_id, stream_id(), enforce: true)
    field(:stream_version, stream_version(), enforce: true)
    field(:causation_id, causation_id())
    field(:correlation_id, correlation_id())
    field(:signal_type, signal_type(), enforce: true)
    field(:data, data(), enforce: true)
    field(:metadata, metadata(), default: %{})
    field(:created_at, created_at(), enforce: true)
  end

  @doc """
  Enrich the signal's metadata with fields from the `RecordedSignal` struct and
  any additional metadata passed as an option.
  """
  @spec enrich_metadata(t(), [{:additional_metadata, map()}]) :: enriched_metadata()
  def enrich_metadata(%RecordedSignal{} = signal, opts) do
    %RecordedSignal{
      signal_id: signal_id,
      signal_number: signal_number,
      stream_id: stream_id,
      stream_version: stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id,
      created_at: created_at,
      metadata: metadata
    } = signal

    additional_metadata = Keyword.get(opts, :additional_metadata, %{})

    %{
      signal_id: signal_id,
      signal_number: signal_number,
      stream_id: stream_id,
      stream_version: stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id,
      created_at: created_at
    }
    |> Map.merge(metadata || %{})
    |> Map.merge(additional_metadata)
  end
end
