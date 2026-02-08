defmodule Jido.Agent.Store.File do
  @moduledoc """
  Compatibility wrapper over `Jido.Storage.File` checkpoint operations.

  This module preserves the legacy `Jido.Agent.Store` API while delegating to
  the unified storage hierarchy.

  ## Options

  - `:path` - Base directory for checkpoint files (required).
  """

  @behaviour Jido.Agent.Store

  alias Jido.Storage.File, as: UnifiedFile

  @impl true
  @spec get(term(), keyword()) :: {:ok, term()} | :not_found | {:error, term()}
  def get(key, opts) do
    UnifiedFile.get_checkpoint(key, normalize_opts(opts))
  end

  @impl true
  @spec put(term(), term(), keyword()) :: :ok | {:error, term()}
  def put(key, dump, opts) do
    UnifiedFile.put_checkpoint(key, dump, normalize_opts(opts))
  end

  @impl true
  @spec delete(term(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts) do
    UnifiedFile.delete_checkpoint(key, normalize_opts(opts))
  end

  defp normalize_opts(opts) do
    [path: Keyword.fetch!(opts, :path)]
  end
end
