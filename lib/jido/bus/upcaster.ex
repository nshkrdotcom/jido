defprotocol Commanded.Signal.Upcaster do
  @moduledoc """
  Protocol to allow an signal to be transformed before being passed to a
  consumer.

  You can use an upcaster to change the shape of an signal (e.g. add a new field
  with a default, rename a field) or rename an signal.

  Upcaster will run for new signals and for historical signals.

  Because the upcaster changes any historical signal to the latest version,
  consumers (aggregates, signal handlers, and process managers) only need
  to support the latest version.

  ## Example

      defimpl Commanded.Signal.Upcaster, for: AnSignal do
        def upcast(%AnSignal{} = signal, _metadata) do
          %AnSignal{name: name} = signal

          %AnSignal{signal | first_name: name}
        end
      end

  ## Metadata

  The `upcast/2` function receives the domain signal and a map of metadata
  associated with that signal. The metadata is provided during command dispatch.

  In addition to the metadata key/values you provide, the following system
  values will be included in the metadata:

    - `application` - the `Commanded.Application` used to read the signal.
    - `signal_id` - a globally unique UUID to identify the signal.
    - `signal_number` - a globally unique, monotonically incrementing integer
      used to order the signal amongst all signals.
    - `stream_id` - the stream identity for the signal.
    - `stream_version` - the version of the stream for the signal.
    - `jido_causation_id` - an optional UUID identifier used to identify which
      command caused the signal.
    - `jido_correlation_id` - an optional UUID identifier used to correlate related
      commands/signals.
    - `created_at` - the datetime, in UTC, indicating when the signal was
      created.

  These key/value metadata pairs will use atom keys to differentiate them from
  the user provided metadata which uses string keys.

  """

  @fallback_to_any true
  @spec upcast(signal :: struct(), metadata :: map()) :: struct()
  def upcast(signal, metadata)
end

defimpl Commanded.Signal.Upcaster, for: Any do
  @moduledoc """
  The default implementation of the `Commanded.Signal.Upcaster`.

  This will return an signal unchanged.
  """

  def upcast(signal, _metadata), do: signal
end
