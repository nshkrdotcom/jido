defmodule Jido.Signal.Bus.Stream do
  use ExDbug, enabled: true
  alias Jido.Signal.Bus.BusState
  alias Jido.Signal.Bus.RecordedSignal
  alias Jido.Signal.Router
  alias Jido.Signal.Dispatch
  alias Jido.Signal
  require Logger

  @doc """
  Filters signals from the bus state's log based on type pattern and timestamp.
  The type pattern is used for matching against the signal's type field.
  """
  def filter(%BusState{} = state, type_pattern, start_timestamp \\ nil, opts \\ []) do
    try do
      batch_size = Keyword.get(opts, :batch_size, 1_000)

      filtered_signals =
        state.log
        |> Enum.filter(fn signal ->
          type_matches =
            case type_pattern do
              "*" -> true
              _ -> signal.type == type_pattern
            end

          timestamp_matches =
            case start_timestamp do
              nil ->
                true

              ts when is_integer(ts) ->
                # Convert signal's created_at to Unix milliseconds for comparison
                signal_ts = DateTime.to_unix(signal.created_at, :millisecond)
                signal_ts > ts

              _ ->
                false
            end

          type_matches and timestamp_matches
        end)
        |> Enum.take(batch_size)

      {:ok, filtered_signals}
    rescue
      error ->
        Logger.error("Error filtering signals: #{inspect(error)}")
        {:error, :filter_failed}
    end
  end

  @doc """
  Publishes signals to the bus, recording them and routing them to subscribers.
  Each signal is routed based on its own type field.
  Only accepts proper Jido.Signal structs to ensure system integrity.
  Signals are recorded and routed in the exact order they are received.
  """
  def publish(%BusState{} = state, signals, start_timestamp \\ 0) when is_list(signals) do
    dbug("publish", signals: signals, start_timestamp: start_timestamp)

    # Validate all signals are proper Jido.Signal structs
    with :ok <- validate_signals(signals) do
      # Convert signals to recorded signals, maintaining strict ordering
      recorded_signals = RecordedSignal.from_signals(signals)

      # Add signals to the log
      new_state = %{state | log: state.log ++ recorded_signals}

      # Route each signal in order
      Enum.each(recorded_signals, fn recorded_signal ->
        # Create a proper Jido.Signal struct for routing
        signal = %Signal{
          id: recorded_signal.id,
          type: recorded_signal.type,
          source: state.name,
          data: recorded_signal.signal.data,
          time: recorded_signal.signal.time,
          datacontenttype: recorded_signal.signal.datacontenttype,
          specversion: recorded_signal.signal.specversion
        }

        with {:ok, dispatch_configs} <- Router.route(state.router, signal) do
          # Dispatch to each target
          Enum.each(dispatch_configs, fn config ->
            case Dispatch.dispatch(signal, config) do
              :ok ->
                :ok

              {:error, reason} ->
                Logger.warning(
                  "Failed to dispatch signal #{recorded_signal.id}: #{inspect(reason)}"
                )
            end
          end)
        else
          {:error, reason} ->
            Logger.warning("Failed to route signal #{recorded_signal.id}: #{inspect(reason)}")
        end
      end)

      {:ok, recorded_signals, new_state}
    end
  end

  @doc """
  Acknowledges a signal for a given subscription.
  """
  def ack(%BusState{} = state, subscription_id, %RecordedSignal{} = signal) do
    dbug("ack", subscription_id: subscription_id, signal: signal)

    {:ok, state}
    # case Map.get(state.subscriptions, subscription_id) do
    #   nil ->
    #     {:error, :subscription_not_found}

    #   subscription ->
    #     case Jido.Signal.Bus.PersistentSubscription.ack(subscription, signal) do
    #       {:ok, updated_subscription} ->
    #         new_state = %{
    #           state
    #           | subscriptions: Map.put(state.subscriptions, subscription_id, updated_subscription)
    #         }

    #         {:ok, new_state}

    #       error ->
    #         error
    #     end
    # end
  end

  # Private Functions

  defp validate_signals(signals) do
    invalid_signals =
      Enum.reject(signals, fn signal ->
        is_struct(signal, Signal)
      end)

    case invalid_signals do
      [] -> :ok
      _ -> {:error, :invalid_signals}
    end
  end
end
