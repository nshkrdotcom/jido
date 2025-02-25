defmodule Jido.Signal.Bus.Snapshot do
  @moduledoc """
  Manages snapshots of the bus's signal log. A snapshot represents a filtered view
  of signals at a particular point in time, filtered by a path pattern.

  Snapshots are immutable once created and are stored in :persistent_term for efficiency.
  The bus state only maintains lightweight references to the snapshots.
  """
  use TypedStruct
  use ExDbug, enabled: false
  alias Jido.Signal.Bus.BusState
  alias Jido.Signal.Bus.Stream
  alias Jido.Signal.ID

  typedstruct module: SnapshotRef do
    @moduledoc """
    A lightweight reference to a snapshot stored in :persistent_term.
    Contains only the metadata needed for listing and lookup.
    """
    field(:id, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:created_at, DateTime.t(), enforce: true)
  end

  typedstruct module: SnapshotData do
    @moduledoc """
    The actual snapshot data stored in :persistent_term.
    Contains the full signal list and metadata.
    """
    field(:id, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:signals, list(Jido.Signal.Bus.RecordedSignal.t()), enforce: true)
    field(:created_at, DateTime.t(), enforce: true)
  end

  @doc """
  Creates a new snapshot of signals matching the given path pattern.
  Stores the snapshot data in :persistent_term and returns a reference.
  Returns {:ok, snapshot_ref, new_state} on success or {:error, reason} on failure.
  """
  @spec create(BusState.t(), String.t()) ::
          {:ok, SnapshotRef.t(), BusState.t()} | {:error, term()}
  def create(state, path) do
    dbug("create", path: path, state: state)

    case Stream.filter(state, path) do
      {:ok, signals} ->
        id = ID.generate!()
        now = DateTime.utc_now()

        # Create the full snapshot data
        snapshot_data = %SnapshotData{
          id: id,
          path: path,
          signals: signals,
          created_at: now
        }

        # Create the lightweight reference
        snapshot_ref = %SnapshotRef{
          id: id,
          path: path,
          created_at: now
        }

        # Store the full data in persistent_term
        :persistent_term.put({__MODULE__, id}, snapshot_data)

        # Store only the reference in the state
        new_state = %{state | snapshots: Map.put(state.snapshots, id, snapshot_ref)}
        {:ok, snapshot_ref, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all snapshot references in the bus state.
  Returns a list of snapshot references.
  """
  @spec list(BusState.t()) :: [SnapshotRef.t()]
  def list(state) do
    dbug("list", state: state)
    Map.values(state.snapshots)
  end

  @doc """
  Reads a snapshot by its ID.
  Returns {:ok, snapshot_data} if found or {:error, :not_found} if not found.
  """
  @spec read(BusState.t(), String.t()) :: {:ok, SnapshotData.t()} | {:error, :not_found}
  def read(state, snapshot_id) do
    dbug("read", snapshot_id: snapshot_id, state: state)

    with {:ok, _ref} <- Map.fetch(state.snapshots, snapshot_id),
         {:ok, data} <- get_snapshot_data(snapshot_id) do
      {:ok, data}
    else
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Deletes a snapshot by its ID.
  Removes both the reference from the state and the data from persistent_term.
  Returns {:ok, new_state} on success or {:error, :not_found} if snapshot doesn't exist.
  """
  @spec delete(BusState.t(), String.t()) :: {:ok, BusState.t()} | {:error, :not_found}
  def delete(state, snapshot_id) do
    dbug("delete", snapshot_id: snapshot_id, state: state)

    case Map.has_key?(state.snapshots, snapshot_id) do
      true ->
        # Remove from persistent_term
        :persistent_term.erase({__MODULE__, snapshot_id})
        # Remove reference from state
        new_state = %{state | snapshots: Map.delete(state.snapshots, snapshot_id)}
        {:ok, new_state}

      false ->
        {:error, :not_found}
    end
  end

  # Private Helpers

  @spec get_snapshot_data(String.t()) :: {:ok, SnapshotData.t()} | :error
  defp get_snapshot_data(snapshot_id) do
    try do
      data = :persistent_term.get({__MODULE__, snapshot_id})
      {:ok, data}
    rescue
      ArgumentError -> :error
    end
  end
end
