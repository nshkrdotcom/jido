# defmodule JidoTest.SensorCounterTest do
#   use ExUnit.Case, async: true
#   alias JidoTest.TestSensors.CounterSensor

#   @moduletag :capture_log

#   import ExUnit.CaptureLog

#   setup context do
#     bus_name = :"test_bus_#{context.test}"
#     start_supervised!({Jido.Bus, name: bus_name})
#     {:ok, bus_name: bus_name}
#   end

#   describe "CounterSensor" do
#     test "initializes with correct default values", %{bus_name: bus_name} do
#       opts = [bus_name: bus_name, stream_id: "test_stream", emit_interval: 1000]
#       {:ok, pid} = CounterSensor.start_link(opts)
#       state = :sys.get_state(pid)

#       assert state.floor == 0
#       assert state.counter == 0
#       assert state.emit_interval == 1000
#     end

#     test "initializes with custom floor value", %{bus_name: bus_name} do
#       opts = [bus_name: bus_name, stream_id: "test_stream", emit_interval: 1000, floor: 10]
#       {:ok, pid} = CounterSensor.start_link(opts)
#       state = :sys.get_state(pid)

#       assert state.floor == 10
#       assert state.counter == 10
#     end

#     test "emits signals at specified interval", %{bus_name: bus_name} do
#       opts = [bus_name: bus_name, stream_id: "test_stream", emit_interval: 100, floor: 5]
#       {:ok, _pid} = CounterSensor.start_link(opts)

#       # Subscribe to the bus stream
#       :ok = Jido.Bus.subscribe(bus_name, "test_stream")

#       # Wait for three emissions
#       assert_receive {:bus_event, ^bus_name, "test_stream", [%{data: %{value: 6}}]}, 200
#       assert_receive {:bus_event, ^bus_name, "test_stream", [%{data: %{value: 7}}]}, 200
#       assert_receive {:bus_event, ^bus_name, "test_stream", [%{data: %{value: 8}}]}, 200
#     end

#     test "handles errors in generate_signal", %{bus_name: bus_name} do
#       defmodule ErrorCounterSensor do
#         @moduledoc false
#         use Jido.Sensor,
#           name: "error_counter_sensor",
#           schema: [
#             emit_interval: [type: :pos_integer, required: true]
#           ]

#         def mount(opts) do
#           schedule_emit(opts)
#           {:ok, opts}
#         end

#         def generate_signal(_) do
#           Logger.warning("Error generating signal: :test_error")
#           {:error, :test_error}
#         end

#         def handle_info(:emit, state) do
#           case generate_signal(state) do
#             {:ok, signal, new_state} ->
#               case publish_signal(signal, new_state) do
#                 :ok ->
#                   schedule_emit(new_state)
#                   {:noreply, new_state}

#                 {:error, reason} ->
#                   Logger.warning("Error publishing signal: #{inspect(reason)}")
#                   schedule_emit(new_state)
#                   {:noreply, new_state}
#               end

#             {:error, reason} ->
#               Logger.warning("Error generating signal: #{inspect(reason)}")
#               schedule_emit(state)
#               {:noreply, state}
#           end
#         end

#         defp schedule_emit(state) do
#           Process.send_after(self(), :emit, state.emit_interval)
#         end
#       end

#       opts = [bus_name: bus_name, stream_id: "test_stream", emit_interval: 100]
#       {:ok, _pid} = ErrorCounterSensor.start_link(opts)

#       # Subscribe to the bus stream
#       :ok = Jido.Bus.subscribe(bus_name, "test_stream")

#       log =
#         capture_log(fn ->
#           # Wait for two emission attempts
#           Process.sleep(250)
#         end)

#       assert log =~ "Error generating signal: :test_error"
#     end
#   end
# end
