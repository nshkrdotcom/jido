defmodule Jido.Bus.Snapshot do
  @moduledoc """
  Contains snapshot data for a source at a specific version.
  """

  use TypedStruct

  @type source_id :: String.t()
  @type source_version :: non_neg_integer()
  @type source_type :: String.t()
  @type data :: term()
  @type metadata :: map()
  @type created_at :: DateTime.t()

  typedstruct do
    field(:source_id, source_id(), enforce: true)
    field(:source_version, source_version(), enforce: true)
    field(:source_type, source_type(), enforce: true)
    field(:data, data(), enforce: true)
    field(:metadata, metadata(), default: %{})
    field(:created_at, created_at(), enforce: true)
  end

  @doc """
  Creates a new snapshot.
  """
  def new(opts) do
    %__MODULE__{
      source_id: Keyword.fetch!(opts, :source_id),
      source_version: Keyword.fetch!(opts, :source_version),
      source_type: Keyword.fetch!(opts, :source_type),
      data: Keyword.fetch!(opts, :data),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: DateTime.utc_now()
    }
  end
end
