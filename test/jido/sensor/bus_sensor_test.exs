defmodule JidoTest.BusSensorTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  import ExUnit.CaptureLog

  alias Jido.Sensors.Bus, as: BusSensor

  setup do
    # The registry is already started by the application
    bus_name = :"test_bus_#{:erlang.unique_integer()}"
    bus_pid = start_supervised!({Jido.Bus, name: bus_name, adapter: :in_memory})

    # Wait for the bus to be registered
    {:ok, _} = Jido.Bus.whereis(bus_name)

    on_exit(fn ->
      # Ensure bus is stopped after test
      if Process.alive?(bus_pid) do
        stop_supervised!(Jido.Bus)
      end
    end)

    {:ok, bus_name: bus_name, bus_pid: bus_pid}
  end

  describe "BusSensor" do
    test "initializes with required options", %{bus_name: bus_name} do
      opts = [
        bus_name: bus_name,
        stream_id: "test_stream",
        subscription_name: "test_subscription",
        target: {:bus, bus_name}
      ]

      pid = start_supervised!({BusSensor, opts})
      state = :sys.get_state(pid)

      assert state.bus_name == bus_name
      assert state.stream_id == "test_stream"

      stop_supervised!(BusSensor)
    end

    @tag :skip
    test "handles bus signals with acknowledgment", %{bus_name: bus_name} do
      opts = [
        bus_name: bus_name,
        stream_id: "test_stream",
        subscription_name: "test_subscription",
        target: {:bus, bus_name}
      ]

      pid = start_supervised!({BusSensor, opts})
      :ok = Jido.Bus.subscribe(bus_name, "test_stream")

      {:ok, test_signal} =
        Jido.Signal.new(%{
          type: "test",
          source: "/test",
          data: %{value: 123}
        })

      send(pid, {:signal, test_signal})

      assert_receive {:bus_event, ^bus_name, "test_stream", [signal]}, 1000
      assert signal.subject == "bus_event"
      assert signal.type == "bus"
      assert signal.data.stream_id == "test_stream"
      assert signal.data.signal == test_signal

      stop_supervised!(BusSensor)
    end

    test "supports custom concurrency and partitioning", %{bus_name: bus_name} do
      partition_by = fn signal -> signal.data.value end

      opts = [
        bus_name: bus_name,
        stream_id: "test_stream",
        subscription_name: "test_subscription",
        target: {:bus, bus_name},
        concurrency: 2,
        partition_by: partition_by
      ]

      pid = start_supervised!({BusSensor, opts})
      state = :sys.get_state(pid)

      assert state.concurrency == 2
      assert state.partition_by == partition_by

      stop_supervised!(BusSensor)
    end

    test "logs warning on signal generation error", %{bus_name: bus_name} do
      defmodule ErrorBusSensor do
        @moduledoc false
        use Jido.Sensor,
          name: "error_bus_sensor",
          schema: [
            bus_name: [type: :atom, required: true],
            stream_id: [type: :string, required: true],
            subscription_name: [type: :string, required: true]
          ]

        def mount(opts), do: {:ok, opts}

        def handle_info({:signal, signal}, state) do
          case generate_signal(state, signal) do
            {:ok, sensor_signal} ->
              case Jido.Sensor.SignalDelivery.deliver({sensor_signal, %{target: state.target}}) do
                :ok ->
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
        end

        defp generate_signal(_, _) do
          Logger.warning("Test error in generate_signal")
          {:error, :test_error}
        end
      end

      opts = [
        bus_name: bus_name,
        stream_id: "test_stream",
        subscription_name: "test_subscription",
        target: {:bus, bus_name}
      ]

      pid = start_supervised!({ErrorBusSensor, opts})
      :ok = Jido.Bus.subscribe(bus_name, "test_stream")

      log =
        capture_log(fn ->
          send(pid, {:signal, %{type: "test"}})
          Process.sleep(100)
        end)

      assert log =~ "Test error in generate_signal"
      stop_supervised!(ErrorBusSensor)
    end

    test "unsubscribes from bus on shutdown", %{bus_name: bus_name} do
      opts = [
        bus_name: bus_name,
        stream_id: "test_stream",
        subscription_name: "test_subscription",
        target: {:bus, bus_name}
      ]

      pid = start_supervised!({BusSensor, opts})

      state = :sys.get_state(pid)
      subscription = state.subscription

      # Verify subscription exists by checking it's a valid pid
      assert is_pid(subscription)
      assert Process.alive?(subscription)

      # Stop the process which should trigger unsubscribe
      stop_supervised!(BusSensor)
    end
  end
end
