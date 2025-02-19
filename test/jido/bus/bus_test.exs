defmodule Jido.BusTest do
  use JidoTest.Case, async: true
  doctest Jido.Bus

  @moduletag :capture_log

  alias Jido.Bus
  alias Jido.Signal
  alias Jido.Bus.Snapshot

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  setup do
    bus_name = :"bus_#{:erlang.unique_integer()}"
    start_supervised!({Bus, name: bus_name, adapter: :in_memory})
    {:ok, pid} = Bus.whereis(bus_name)
    %{bus: pid, bus_name: bus_name}
  end

  describe "via_tuple/2" do
    test "returns via tuple with default registry" do
      assert Bus.via_tuple(:my_bus) == {:via, Registry, {Jido.Bus.Registry, :my_bus}}
    end

    test "returns via tuple with custom registry" do
      assert Bus.via_tuple(:my_bus, registry: MyApp.Registry) ==
               {:via, Registry, {MyApp.Registry, :my_bus}}
    end
  end

  describe "whereis/2" do
    test "returns pid for running bus", %{bus_name: bus_name} do
      assert {:ok, pid} = Bus.whereis(bus_name)
      assert is_pid(pid)
    end

    test "returns error for non-existent bus" do
      assert {:error, :not_found} = Bus.whereis(:nonexistent)
    end
  end

  describe "publish/5" do
    test "publishes signals to stream", %{bus: bus} do
      stream_id = "test-stream"
      signals = build_signals(2)

      assert :ok = Bus.publish(bus, stream_id, 0, signals)

      # Verify signals can be replayed
      stream = Bus.replay(bus, stream_id)
      assert coerce(Enum.to_list(stream)) == coerce(signals)
    end

    test "fails with wrong expected version when no stream", %{bus: bus} do
      assert {:error, :wrong_expected_version} ==
               Bus.publish(bus, "stream", 1, build_signals(1))
    end

    test "fails with wrong expected version", %{bus: bus} do
      assert :ok = Bus.publish(bus, "stream", 0, build_signals(3))

      assert {:error, :wrong_expected_version} ==
               Bus.publish(bus, "stream", 0, build_signals(1))

      assert {:error, :wrong_expected_version} ==
               Bus.publish(bus, "stream", 1, build_signals(1))

      assert :ok = Bus.publish(bus, "stream", 3, build_signals(1))
    end

    test "publishes with :any_version", %{bus: bus} do
      assert :ok = Bus.publish(bus, "stream", :any_version, build_signals(3))
      assert :ok = Bus.publish(bus, "stream", :any_version, build_signals(2))
    end

    test "publishes with :no_stream", %{bus: bus} do
      assert :ok = Bus.publish(bus, "stream", :no_stream, build_signals(2))
      assert {:error, :stream_exists} = Bus.publish(bus, "stream", :no_stream, build_signals(1))
    end

    test "publishes with :stream_exists", %{bus: bus} do
      assert {:error, :stream_not_found} =
               Bus.publish(bus, "stream", :stream_exists, build_signals(1))

      assert :ok = Bus.publish(bus, "stream", :no_stream, build_signals(2))
      assert :ok = Bus.publish(bus, "stream", :stream_exists, build_signals(1))
    end
  end

  describe "replay/2" do
    test "returns error for unknown stream", %{bus: bus} do
      assert {:error, :stream_not_found} = Bus.replay(bus, "unknownstream")
    end

    test "reads signals from stream", %{bus: bus} do
      correlation_id = Jido.Util.generate_id()
      causation_id = Jido.Util.generate_id()
      signals = build_signals(4, correlation_id, causation_id)

      assert :ok = Bus.publish(bus, "stream", 0, signals)

      stream = Bus.replay(bus, "stream")
      read_signals = Enum.to_list(stream)
      assert length(read_signals) == 4
      assert coerce(signals) == coerce(read_signals)

      Enum.each(read_signals, fn signal ->
        assert signal.correlation_id == correlation_id
        assert signal.causation_id == causation_id
        assert signal.jido_metadata == %{"metadata" => "value"}
        assert %DateTime{} = signal.created_at
      end)
    end
  end

  describe "subscribe/2" do
    @tag :skip
    test "creates transient subscription", %{bus: bus} do
      stream_id = "test-stream"
      assert :ok = Bus.subscribe(bus, stream_id)
      assert_receive {:subscribed, subscription}

      signals = build_signals(1)
      :ok = Bus.publish(bus, stream_id, 0, signals)

      assert_receive {:signals, ^subscription, received_signals}
      assert coerce(received_signals) == coerce(signals)
    end
  end

  describe "subscribe_persistent/6" do
    test "creates persistent subscription", %{bus: bus} do
      {:ok, subscription} =
        Bus.subscribe_persistent(bus, "stream1", "subscriber", self(), :origin, [])

      assert_receive {:subscribed, ^subscription}

      :ok = Bus.publish(bus, "stream1", 0, build_signals(1))
      :ok = Bus.publish(bus, "stream2", 0, build_signals(2))
      :ok = Bus.publish(bus, "stream3", 0, build_signals(3))

      assert_receive {:signals, received_signals}
      assert length(received_signals) == 1
    end

    @tag :skip
    test "resumes from last position", %{bus: bus} do
      {:ok, subscription} =
        Bus.subscribe_persistent(bus, :all, "subscriber", self(), :origin, [])

      assert_receive {:subscribed, ^subscription}

      :ok = Bus.publish(bus, "stream1", 0, build_signals(1))

      :ok = Bus.unsubscribe(bus, subscription)

      :ok = Bus.publish(bus, "stream2", 0, build_signals(2))
      :ok = Bus.publish(bus, "stream3", 0, build_signals(3))

      refute_receive {:signals, _}

      {:ok, subscription2} =
        Bus.subscribe_persistent(bus, :all, "subscriber", self(), :origin, [])

      assert_receive {:subscribed, ^subscription2}

      # Wait for all signals to be received
      assert_receive {:signals, signals1}
      assert_receive {:signals, signals2}
      more_signals = signals1 ++ signals2
      assert length(more_signals) == 5
    end
  end

  describe "snapshots" do
    test "manages snapshots", %{bus: bus} do
      snapshot = build_snapshot_data(100)

      assert {:error, :snapshot_not_found} = Bus.read_snapshot(bus, snapshot.source_id)

      assert :ok = Bus.record_snapshot(bus, snapshot)
      assert {:ok, read_snapshot} = Bus.read_snapshot(bus, snapshot.source_id)
      assert snapshot_timestamps_within_delta?(read_snapshot, snapshot, 60)

      assert :ok = Bus.delete_snapshot(bus, snapshot.source_id)
      assert {:error, :snapshot_not_found} = Bus.read_snapshot(bus, snapshot.source_id)
    end
  end

  defp build_signal(account_number, correlation_id, causation_id) do
    %Signal{
      id: correlation_id,
      source: causation_id,
      type: "#{__MODULE__}.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      jido_metadata: %{"metadata" => "value"}
    }
  end

  defp build_signals(
         count,
         correlation_id \\ Jido.Util.generate_id(),
         causation_id \\ Jido.Util.generate_id()
       )

  defp build_signals(count, correlation_id, causation_id) do
    for account_number <- 1..count,
        do: build_signal(account_number, correlation_id, causation_id)
  end

  defp build_snapshot_data(account_number) do
    %Snapshot{
      source_id: Jido.Util.generate_id(),
      source_version: account_number,
      source_type: "#{__MODULE__}.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      jido_metadata: nil,
      created_at: DateTime.utc_now()
    }
  end

  defp snapshot_timestamps_within_delta?(snapshot, other_snapshot, delta_seconds) do
    DateTime.diff(snapshot.created_at, other_snapshot.created_at, :second) < delta_seconds
  end

  defp coerce(signals) do
    Enum.map(signals, fn
      %Signal{} = signal ->
        %{
          causation_id: signal.source,
          correlation_id: signal.id,
          data: signal.data,
          jido_metadata: signal.jido_metadata
        }

      recorded_signal ->
        %{
          causation_id: recorded_signal.causation_id,
          correlation_id: recorded_signal.correlation_id,
          data: recorded_signal.data,
          jido_metadata: recorded_signal.jido_metadata
        }
    end)
  end
end
