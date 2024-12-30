defmodule JidoTest.Sensor.Examples.RegistrationCounterSensorTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log
  defmodule RegistrationCounterSensor do
    @moduledoc """
    Tracks user registration success and failure metrics, emitting signals with statistics.
    """
    use Jido.Sensor,
      name: "registration_counter_sensor",
      description: "Monitors registration successes and failures",
      category: :metrics,
      tags: [:registration, :counter],
      vsn: "1.0.0",
      schema: [
        emit_interval: [
          type: :pos_integer,
          default: 1000,
          doc: "Interval between metric emissions in ms"
        ]
      ]

    def mount(opts) do
      state =
        Map.merge(opts, %{
          successful: 0,
          failed: 0
        })

      schedule_emit(state)
      {:ok, state}
    end

    def generate_signal(state) do
      total = state.successful + state.failed
      success_rate = if total > 0, do: state.successful / total * 100, else: 0

      Jido.Signal.new(%{
        source: "#{state.sensor.name}:#{state.id}",
        subject: "registration_counts",
        type: "registration.metrics",
        data: %{
          successful: state.successful,
          failed: state.failed,
          total: total,
          success_rate: success_rate
        }
      })
    end

    def handle_info(:emit, state) do
      with {:ok, signal} <- generate_signal(state),
           :ok <- Phoenix.PubSub.broadcast(state.pubsub, state.topic, signal) do
        schedule_emit(state)
        {:noreply, state}
      else
        error ->
          Logger.warning("Error generating/publishing signal: #{inspect(error)}")
          schedule_emit(state)
          {:noreply, state}
      end
    end

    def handle_info({:registration, :success}, state) do
      new_state = %{state | successful: state.successful + 1}

      with {:ok, signal} <- generate_signal(new_state),
           :ok <- Phoenix.PubSub.broadcast(state.pubsub, state.topic, signal) do
        {:noreply, new_state}
      else
        error ->
          Logger.warning("Error broadcasting success signal: #{inspect(error)}")
          {:noreply, new_state}
      end
    end

    def handle_info({:registration, :failure}, state) do
      new_state = %{state | failed: state.failed + 1}

      with {:ok, signal} <- generate_signal(new_state),
           :ok <- Phoenix.PubSub.broadcast(state.pubsub, state.topic, signal) do
        {:noreply, new_state}
      else
        error ->
          Logger.warning("Error broadcasting failure signal: #{inspect(error)}")
          {:noreply, new_state}
      end
    end

    defp schedule_emit(state) do
      Process.send_after(self(), :emit, state.emit_interval)
    end
  end

  setup do
    start_supervised!({Phoenix.PubSub, name: TestPubSub})
    :ok
  end

  describe "RegistrationCounterSensor" do
    test "initializes with correct default values" do
      {:ok, pid} = start_supervised({RegistrationCounterSensor, pubsub: TestPubSub})
      state = :sys.get_state(pid)

      assert state.successful == 0
      assert state.failed == 0
      assert state.emit_interval == 1000
    end

    test "tracks successful registrations" do
      {:ok, pid} =
        start_supervised({RegistrationCounterSensor, pubsub: TestPubSub, emit_interval: 100})

      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      # Record successes and wait for each signal
      send(pid, {:registration, :success})
      assert_receive signal1, 200
      assert signal1.data.successful == 1

      send(pid, {:registration, :success})
      assert_receive signal2, 200
      assert signal2.data.successful == 2
      assert signal2.data.failed == 0
      assert signal2.data.total == 2
      assert signal2.data.success_rate == 100.0
    end

    test "tracks failed registrations" do
      {:ok, pid} =
        start_supervised({RegistrationCounterSensor, pubsub: TestPubSub, emit_interval: 100})

      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      # Record some failures
      send(pid, {:registration, :failure})
      assert_receive signal1, 200
      assert signal1.data.failed == 1

      # Wait for signal
      send(pid, {:registration, :failure})
      assert_receive signal2, 200
      assert signal2.data.successful == 0
      assert signal2.data.failed == 2
      assert signal2.data.total == 2
      assert signal2.data.success_rate == 0.0
    end

    test "calculates mixed success rate" do
      {:ok, pid} =
        start_supervised({RegistrationCounterSensor, pubsub: TestPubSub, emit_interval: 100})

      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      # Mix of successes and failures
      send(pid, {:registration, :success})
      assert_receive signal1, 200
      assert signal1.data.successful == 1
      assert signal1.data.failed == 0
      assert signal1.data.total == 1

      send(pid, {:registration, :success})
      assert_receive signal2, 200
      assert signal2.data.successful == 2
      assert signal2.data.failed == 0
      assert signal2.data.total == 2
      assert signal2.data.success_rate == 100.0

      send(pid, {:registration, :failure})
      assert_receive signal3, 200
      assert signal3.data.successful == 2
      assert signal3.data.failed == 1
      assert signal3.data.total == 3
      assert_in_delta signal3.data.success_rate, 66.67, 0.01
    end

    test "emits regular metric updates" do
      {:ok, pid} =
        start_supervised({RegistrationCounterSensor, pubsub: TestPubSub, emit_interval: 100})

      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      # Should get regular updates even without activity
      assert_receive signal1, 200
      assert signal1.type == "registration.metrics"
      assert signal1.data.total == 0

      assert_receive signal2, 200
      assert signal2.type == "registration.metrics"
    end
  end
end
