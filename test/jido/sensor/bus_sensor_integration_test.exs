# defmodule JidoTest.Sensor.BusIntegrationTest do
#   use ExUnit.Case, async: true

#   @moduletag :capture_log

#   defmodule BusEnabledSensor do
#     use Jido.Sensor,
#       name: "bus_enabled_sensor",
#       description: "A sensor that emits to a bus",
#       category: :test,
#       tags: [:test, :bus],
#       vsn: "1.0.0",
#       schema: [
#         test_param: [type: :integer, default: 0]
#       ]

#     def mount(opts) do
#       require Logger
#       Logger.debug("Mounting sensor with options: #{inspect(opts)}")
#       {:ok, Map.put(opts, :mounted, true)}
#     end

#     def generate_signal(state) do
#       require Logger
#       Logger.debug("Generating signal with state: #{inspect(state)}")

#       signal =
#         Jido.Signal.new(%{
#           source: "#{state.sensor.name}:#{state.id}",
#           subject: "test_signal",
#           type: "test_signal",
#           data: %{value: state.test_param},
#           timestamp: DateTime.utc_now()
#         })

#       {:ok, signal}
#     end

#     def before_publish(signal, _state) do
#       signal
#     end
#   end

#   setup do
#     bus_name = :"bus_#{:erlang.unique_integer()}"
#     start_supervised!({Jido.Bus, name: bus_name})
#     %{bus: bus_name}
#   end

#   describe "Bus-enabled sensor" do
#     test "emits signals to the configured bus", %{bus: bus} do
#       opts = [
#         bus_name: bus,
#         stream_id: "test-stream",
#         test_param: 42
#       ]

#       assert {:ok, pid} = BusEnabledSensor.start_link(opts)
#       assert Process.alive?(pid)

#       # Get and inspect the state
#       state = :sys.get_state(pid)
#       require Logger
#       Logger.debug("Initial sensor state: #{inspect(state)}")

#       # Generate and publish a signal
#       {:ok, signal} = BusEnabledSensor.generate_signal(state)
#       assert :ok = Jido.Bus.publish(bus, "test-stream", [signal], [])

#       # Subscribe to the bus stream
#       :ok = Jido.Bus.subscribe(bus, "test-stream")

#       # Wait for signal
#       assert_receive {:bus_event, ^bus, "test-stream", [signal]}, 1000
#       assert signal.subject == "test_signal"
#       assert signal.data.value == 42
#     end

#     test "fails to start without required bus configuration" do
#       opts = [stream_id: "test-stream"]
#       assert {:error, reason} = BusEnabledSensor.start_link(opts)
#       assert reason =~ "required :bus_name option not found"
#     end
#   end
# end
