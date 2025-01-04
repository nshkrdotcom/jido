defmodule Commanded.Signal.Mapper do
  @moduledoc """
  Map signals to/from the structs used for persistence.

  ## Example

  Map domain signal structs to `Jido.Bus.Signal` structs in
  preparation for appending to the configured signal store:

      signals = [%ExampleSignal1{}, %ExampleSignal2{}]
      signal_data = Commanded.Signal.Mapper.map_to_signal_data(signals)

      :ok = Jido.Bus.publish("stream-1234", :any_version, signal_data)

  """

  alias Jido.Bus.TypeProvider
  alias Jido.Bus.{Signal, RecordedSignal}

  @type signal :: struct

  @doc """
  Map a domain signal (or list of signals) to an
  `Jido.Bus.Signal` struct (or list of structs).

  Optionally, include the `jido_causation_id`, `jido_correlation_id`, and `metadata`
  associated with the signal(s).

  ## Examples

      signal_data = Commanded.Signal.Mapper.map_to_signal_data(%ExampleSignal{})

      signal_data =
        Commanded.Signal.Mapper.map_to_signal_data(
          [
            %ExampleSignal1{},
            %ExampleSignal2{}
          ],
          jido_causation_id: Commanded.UUID.uuid4(),
          jido_correlation_id: Commanded.UUID.uuid4(),
          metadata: %{"user_id" => user_id}
        )

  """
  def map_to_signal_data(signals, fields \\ [])

  @spec map_to_signal_data(list(signal), Keyword.t()) :: list(Signal.t())
  def map_to_signal_data(signals, fields) when is_list(signals) do
    Enum.map(signals, &map_to_signal_data(&1, fields))
  end

  @spec map_to_signal_data(struct, Keyword.t()) :: Signal.t()
  def map_to_signal_data(signal, fields) do
    %Signal{
      jido_causation_id: Keyword.get(fields, :jido_causation_id),
      jido_correlation_id: Keyword.get(fields, :jido_correlation_id),
      type: TypeProvider.to_string(signal),
      data: signal,
      metadata: Keyword.get(fields, :metadata, %{})
    }
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
