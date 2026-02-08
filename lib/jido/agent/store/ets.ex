defmodule Jido.Agent.Store.ETS do
  @moduledoc """
  Compatibility wrapper over `Jido.Storage.ETS` checkpoint operations.

  This module preserves the legacy `Jido.Agent.Store` contract while delegating
  storage behavior to the unified storage hierarchy.

  ## Options

  - `:table` - ETS table name (required).
  """

  @behaviour Jido.Agent.Store

  alias Jido.Storage.ETS, as: UnifiedETS

  @impl true
  @spec get(term(), keyword()) :: {:ok, term()} | :not_found | {:error, term()}
  def get(key, opts) do
    UnifiedETS.get_checkpoint(key, normalize_opts(opts))
  end

  @impl true
  @spec put(term(), term(), keyword()) :: :ok | {:error, term()}
  def put(key, dump, opts) do
    UnifiedETS.put_checkpoint(key, dump, normalize_opts(opts))
  end

  @impl true
  @spec delete(term(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts) do
    UnifiedETS.delete_checkpoint(key, normalize_opts(opts))
  end

  @doc """
  Deletes the configured ETS table set if present.
  """
  @spec cleanup(keyword()) :: :ok | {:error, term()}
  def cleanup(opts) do
    UnifiedETS.cleanup(normalize_opts(opts))
  end

  defp normalize_opts(opts) do
    [table: Keyword.fetch!(opts, :table)]
  end
end
