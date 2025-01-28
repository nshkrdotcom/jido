defmodule Jido.Sensors.Bus do
  @moduledoc """
  A sensor that subscribes to a Jido.Bus and emits signals based on bus events.
  """
  use Jido.Sensor,
    name: "bus_sensor",
    description: "Monitors events from a Jido.Bus instance",
    category: :bus,
    tags: [:bus, :events],
    vsn: "1.0.0",
    schema: [
      bus_name: [type: :atom, required: true],
      stream_id: [type: :string, required: true],
      subscription_name: [type: :string, required: true],
      concurrency: [type: :integer, default: 1],
      partition_by: [type: :any, default: nil]
    ]

  require Logger

  @impl true
  def mount(opts) do
    subscription_opts = [
      concurrency_limit: opts.concurrency,
      partition_by: opts.partition_by
    ]

    with {:ok, subscription} <-
           Jido.Bus.subscribe_persistent(
             opts.bus_name,
             opts.stream_id,
             opts.subscription_name,
             self(),
             :origin,
             subscription_opts
           ) do
      state = Map.put(opts, :subscription, subscription)
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:subscribed, _subscription}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    try do
      case generate_signal(state, signal) do
        %Jido.Signal{} = sensor_signal ->
          case Jido.Sensor.SignalDelivery.deliver({sensor_signal, %{target: state.target}}) do
            :ok ->
              # Acknowledge the signal after successful processing
              :ok = Jido.Bus.ack(state.bus_name, state.subscription, signal)
              {:noreply, state}

            {:error, reason} ->
              Logger.warning("Error publishing signal: #{inspect(reason)}")
              {:noreply, state}
          end

        {:error, reason} ->
          Logger.warning("Error generating signal: #{inspect(reason)}")
          {:noreply, state}
      end
    rescue
      e ->
        Logger.error("Error processing signal: #{inspect(e)}")
        {:noreply, state}
    end
  end

  @impl true
  def get_config do
    {:ok,
     %{
       bus_name: nil,
       stream_id: nil,
       subscription_name: nil,
       concurrency: 1,
       partition_by: nil
     }}
  end

  @impl true
  def set_config(config) do
    {:ok, config}
  end

  # Generate a new signal from the bus event
  defp generate_signal(state, bus_signal) do
    try do
      case Jido.Signal.new(%{
             source: "#{state.sensor.name}:#{state.id}",
             subject: "bus_event",
             type: "bus",
             data: %{
               stream_id: state.stream_id,
               signal: bus_signal
             },
             timestamp: DateTime.utc_now()
           }) do
        {:ok, signal} -> signal
        error -> error
      end
    rescue
      e ->
        {:error, {:signal_generation_error, e}}
    end
  end

  @impl true
  def shutdown(state) do
    try do
      case Jido.Bus.whereis(state.bus_name) do
        {:ok, _} ->
          :ok = Jido.Bus.unsubscribe(state.bus_name, state.subscription)
          {:ok, state}

        _ ->
          {:ok, state}
      end
    rescue
      _ -> {:ok, state}
    end
  end
end
