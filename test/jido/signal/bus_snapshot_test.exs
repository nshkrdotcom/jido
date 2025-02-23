defmodule Jido.Signal.Bus.SnapshotTest do
  use ExUnit.Case, async: true
  alias Jido.Signal.Bus.BusState
  alias Jido.Signal.Bus.Snapshot
  alias Jido.Signal.Bus.RecordedSignal
  alias Jido.Signal.Router
  alias Jido.Signal

  @moduletag :capture_log

  setup do
    # Create a test bus state with some signals
    {:ok, signal1} =
      Signal.new(%{
        type: "test.signal.1",
        source: "/test",
        data: %{value: 1}
      })

    {:ok, signal2} =
      Signal.new(%{
        type: "test.signal.2",
        source: "/test",
        data: %{value: 2}
      })

    recorded_signals = [
      %RecordedSignal{
        id: "1",
        correlation_id: nil,
        type: "test.signal.1",
        signal: signal1,
        created_at: DateTime.utc_now()
      },
      %RecordedSignal{
        id: "2",
        correlation_id: nil,
        type: "test.signal.2",
        signal: signal2,
        created_at: DateTime.utc_now()
      }
    ]

    state = %BusState{
      id: "test-bus",
      name: :test_bus,
      router: Router.new!(),
      log: recorded_signals,
      snapshots: %{}
    }

    {:ok, state: state}
  end

  describe "create/2" do
    test "creates a snapshot with filtered signals", %{state: state} do
      {:ok, snapshot_ref, new_state} = Snapshot.create(state, "test.signal.1")

      # Verify the reference
      assert snapshot_ref.path == "test.signal.1"
      assert is_binary(snapshot_ref.id)
      assert %DateTime{} = snapshot_ref.created_at
      assert Map.has_key?(new_state.snapshots, snapshot_ref.id)

      # Verify the actual data in persistent_term
      {:ok, snapshot_data} = Snapshot.read(new_state, snapshot_ref.id)
      assert length(snapshot_data.signals) == 1
      assert hd(snapshot_data.signals).type == "test.signal.1"
    end

    test "creates a snapshot with all signals using wildcard", %{state: state} do
      {:ok, snapshot_ref, new_state} = Snapshot.create(state, "*")

      # Verify the reference
      assert snapshot_ref.path == "*"
      assert Map.has_key?(new_state.snapshots, snapshot_ref.id)

      # Verify the actual data
      {:ok, snapshot_data} = Snapshot.read(new_state, snapshot_ref.id)
      assert length(snapshot_data.signals) == 2
    end

    test "creates an empty snapshot when no signals match path", %{state: state} do
      {:ok, snapshot_ref, new_state} = Snapshot.create(state, "non.existent.path")

      # Verify the reference
      assert snapshot_ref.path == "non.existent.path"
      assert Map.has_key?(new_state.snapshots, snapshot_ref.id)

      # Verify the actual data
      {:ok, snapshot_data} = Snapshot.read(new_state, snapshot_ref.id)
      assert Enum.empty?(snapshot_data.signals)
    end
  end

  describe "list/1" do
    test "returns empty list when no snapshots exist", %{state: state} do
      assert Snapshot.list(state) == []
    end

    test "returns list of all snapshot references", %{state: state} do
      {:ok, snapshot_ref1, state} = Snapshot.create(state, "test.signal.1")
      {:ok, snapshot_ref2, state} = Snapshot.create(state, "test.signal.2")

      snapshot_refs = Snapshot.list(state)
      assert length(snapshot_refs) == 2
      assert Enum.member?(snapshot_refs, snapshot_ref1)
      assert Enum.member?(snapshot_refs, snapshot_ref2)
    end
  end

  describe "read/2" do
    test "returns snapshot data by id", %{state: state} do
      {:ok, snapshot_ref, state} = Snapshot.create(state, "test.signal.1")
      {:ok, snapshot_data} = Snapshot.read(state, snapshot_ref.id)

      assert snapshot_data.id == snapshot_ref.id
      assert snapshot_data.path == snapshot_ref.path
      assert snapshot_data.created_at == snapshot_ref.created_at
      assert length(snapshot_data.signals) == 1
      assert hd(snapshot_data.signals).type == "test.signal.1"
    end

    test "returns error when snapshot not found", %{state: state} do
      assert {:error, :not_found} = Snapshot.read(state, "non-existent-id")
    end
  end

  describe "delete/2" do
    test "deletes existing snapshot from both state and persistent_term", %{state: state} do
      {:ok, snapshot_ref, state} = Snapshot.create(state, "test.signal.1")
      {:ok, new_state} = Snapshot.delete(state, snapshot_ref.id)

      # Verify removed from state
      refute Map.has_key?(new_state.snapshots, snapshot_ref.id)
      # Verify removed from persistent_term
      assert {:error, :not_found} = Snapshot.read(new_state, snapshot_ref.id)
    end

    test "returns error when deleting non-existent snapshot", %{state: state} do
      assert {:error, :not_found} = Snapshot.delete(state, "non-existent-id")
    end

    test "maintains other snapshots when deleting one", %{state: state} do
      {:ok, snapshot_ref1, state} = Snapshot.create(state, "test.signal.1")
      {:ok, snapshot_ref2, state} = Snapshot.create(state, "test.signal.2")
      {:ok, new_state} = Snapshot.delete(state, snapshot_ref1.id)

      # Verify first snapshot is completely removed
      refute Map.has_key?(new_state.snapshots, snapshot_ref1.id)
      assert {:error, :not_found} = Snapshot.read(new_state, snapshot_ref1.id)

      # Verify second snapshot is still intact
      assert Map.has_key?(new_state.snapshots, snapshot_ref2.id)
      {:ok, snapshot_data2} = Snapshot.read(new_state, snapshot_ref2.id)
      assert snapshot_data2.id == snapshot_ref2.id
    end
  end
end
