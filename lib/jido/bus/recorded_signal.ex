defmodule Jido.Bus.RecordedSignal do
  @moduledoc false

  alias Jido.Bus.RecordedSignal

  @type causation_id :: uuid() | nil
  @type correlation_id :: uuid() | nil
  @type created_at :: DateTime.t()
  @type data :: domain_signal()
  @type domain_signal :: struct()
  @type signal_id :: uuid()
  @type signal_number :: non_neg_integer()
  @type type :: String.t()
  @type jido_metadata :: map()
  @type stream_id :: String.t()
  @type stream_version :: non_neg_integer()
  @type uuid :: String.t()
  @type signal :: struct()

  @type t :: %RecordedSignal{
          signal_id: signal_id(),
          signal_number: signal_number(),
          stream_id: stream_id(),
          stream_version: stream_version(),
          causation_id: causation_id(),
          correlation_id: correlation_id(),
          type: type(),
          data: data(),
          jido_metadata: jido_metadata(),
          created_at: created_at()
        }

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

  defstruct [
    :signal_id,
    :signal_number,
    :stream_id,
    :stream_version,
    :causation_id,
    :correlation_id,
    :type,
    :data,
    :created_at,
    jido_metadata: %{}
  ]

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
      jido_metadata: jido_metadata
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
    |> Map.merge(jido_metadata || %{})
    |> Map.merge(additional_metadata)
  end

  @doc """
  Map a list of `Jido.Bus.RecordedSignal` structs to their signal data.
  """
  @spec map_from_recorded_signals(list(RecordedSignal.t())) :: [signal]
  def map_from_recorded_signals(recorded_signals) when is_list(recorded_signals) do
    Enum.map(recorded_signals, &map_from_recorded_signal/1)
  end

  @doc """
  Map an `Jido.Bus.RecordedSignal` struct to its signal data.
  """
  @spec map_from_recorded_signal(RecordedSignal.t()) :: signal
  def map_from_recorded_signal(%RecordedSignal{data: data}), do: data
end
