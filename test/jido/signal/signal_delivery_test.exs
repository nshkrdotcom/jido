defmodule Jido.Sensor.SignalDeliveryTest do
  use ExUnit.Case, async: true
  alias Jido.Sensor.SignalDelivery

  describe "validate_delivery_target/1" do
    test "validates pid target" do
      pid = self()
      assert {:ok, {:pid, ^pid}} = SignalDelivery.validate_delivery_target({:pid, pid})
    end

    test "validates bus target" do
      assert {:ok, {:bus, :test_bus}} = SignalDelivery.validate_delivery_target({:bus, :test_bus})
    end

    test "validates named process target" do
      assert {:ok, {:name, :test_process}} =
               SignalDelivery.validate_delivery_target({:name, :test_process})
    end

    test "validates remote target" do
      pid = self()

      assert {:ok, {:remote, {:node1, {:pid, ^pid}}}} =
               SignalDelivery.validate_delivery_target({:remote, {:node1, {:pid, pid}}})
    end

    test "returns error for invalid remote target" do
      assert {:error, "invalid delivery target format"} =
               SignalDelivery.validate_delivery_target({:remote, {:node1, "invalid"}})
    end

    test "returns error for invalid target format" do
      assert {:error, "invalid delivery target format"} =
               SignalDelivery.validate_delivery_target("invalid")

      assert {:error, "invalid delivery target format"} =
               SignalDelivery.validate_delivery_target({:invalid, self()})

      assert {:error, "invalid delivery target format"} =
               SignalDelivery.validate_delivery_target({:pid, "not_a_pid"})
    end
  end

  describe "validate_delivery_opts/1" do
    test "validates valid delivery options" do
      opts = [
        target: {:pid, self()},
        delivery_mode: :async,
        stream: "test_stream",
        version: 1,
        publish_opts: [retain: true]
      ]

      assert {:ok, validated} = SignalDelivery.validate_delivery_opts(opts)
      assert validated.target == {:pid, self()}
      assert validated.delivery_mode == :async
      assert validated.stream == "test_stream"
      assert validated.version == 1
      assert validated.publish_opts == [retain: true]
    end

    test "returns error for invalid target type" do
      opts = [target: "invalid"]

      assert {:error, %NimbleOptions.ValidationError{}} =
               SignalDelivery.validate_delivery_opts(opts)
    end

    test "returns error for invalid delivery mode" do
      opts = [target: {:pid, self()}, delivery_mode: :invalid]

      assert {:error, %NimbleOptions.ValidationError{}} =
               SignalDelivery.validate_delivery_opts(opts)
    end

    test "uses default values when not provided" do
      opts = [target: {:pid, self()}]
      assert {:ok, validated} = SignalDelivery.validate_delivery_opts(opts)
      assert validated.delivery_mode == :async
      assert validated.stream == "default"
      assert validated.version == :any_version
      assert validated.publish_opts == []
    end
  end

  describe "deliver/1" do
    setup do
      test_signal = %Jido.Signal{
        id: "test_id",
        source: "test",
        type: "test.signal",
        subject: "test",
        data: %{value: 42},
        time: DateTime.utc_now()
      }

      {:ok, signal: test_signal}
    end

    test "delivers to pid asynchronously", %{signal: signal} do
      routing_opts = %{target: {:pid, self()}, delivery_mode: :async}
      assert :ok = SignalDelivery.deliver({signal, routing_opts})
      assert_receive {:signal, ^signal}
    end

    test "delivers to pid synchronously", %{signal: signal} do
      # Create a test process that will respond to GenServer.call
      test_process =
        spawn(fn ->
          receive do
            {:"$gen_call", from, {:signal, received_signal}} ->
              GenServer.reply(from, {:ok, received_signal})
          end
        end)

      routing_opts = %{target: {:pid, test_process}, delivery_mode: :sync}
      assert {:ok, ^signal} = SignalDelivery.deliver({signal, routing_opts})
    end

    test "delivers to bus", %{signal: signal} do
      bus_name = :"test_bus_#{:erlang.unique_integer()}"
      start_supervised!({Jido.Bus, name: bus_name})

      routing_opts = %{
        target: {:bus, bus_name},
        stream: "test_stream",
        version: :any_version,
        publish_opts: []
      }

      assert :ok = SignalDelivery.deliver({signal, routing_opts})
    end

    test "delivers to named process", %{signal: signal} do
      name = :"test_process_#{:erlang.unique_integer()}"
      Process.register(self(), name)

      routing_opts = %{target: {:name, name}, delivery_mode: :async}
      assert :ok = SignalDelivery.deliver({signal, routing_opts})
      assert_receive {:signal, ^signal}
    end

    test "returns error when named process not found", %{signal: signal} do
      routing_opts = %{target: {:name, :nonexistent_process}, delivery_mode: :async}
      assert {:error, :process_not_found} = SignalDelivery.deliver({signal, routing_opts})
    end
  end
end
