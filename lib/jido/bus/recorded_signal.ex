defmodule Jido.Bus.RecordedSignal do
  @moduledoc """
  Contains the persisted stream identity and signal data for a single signal.

  Signals are immutable once recorded.

  ## Recorded signal fields

    - `signal_id` - a globally unique UUID to identify the signal
    - `signal_number` - a globally unique, monotonically incrementing and gapless integer
    - `stream_id` - the stream identity for the signal
    - `stream_version` - the version of the stream for the signal
    - `signal` - the signal data as a Signal struct
    - `created_at` - the datetime, in UTC, indicating when the signal was created
  """

  use TypedStruct

  alias Jido.Signal

  @type signal_id :: String.t()
  @type signal_number :: non_neg_integer()
  @type stream_id :: String.t()
  @type stream_version :: non_neg_integer()
  @type created_at :: DateTime.t()

  typedstruct do
    field(:signal_id, signal_id(), enforce: true)
    field(:signal_number, signal_number(), enforce: true)
    field(:stream_id, stream_id(), enforce: true)
    field(:stream_version, stream_version(), enforce: true)
    field(:signal, Signal.t(), enforce: true)
    field(:created_at, created_at(), enforce: true)
  end
end
