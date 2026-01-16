defmodule Jido.Agent.Store.ETS do
  @moduledoc """
  ETS-based agent store adapter.

  Fast in-memory storage for agent hibernate/thaw. Not restart-safe -
  all data is lost when the BEAM stops.

  ## Usage

      Jido.Agent.InstanceManager.child_spec(
        name: :sessions,
        agent: MyAgent,
        persistence: [
          store: {Jido.Agent.Store.ETS, table: :my_agent_cache}
        ]
      )

  ## Options

  - `:table` - ETS table name (required). Table is created if it doesn't exist.
  """
  @behaviour Jido.Agent.Store

  @impl true
  def get(key, opts) do
    table = Keyword.fetch!(opts, :table)
    ensure_table(table)

    case :ets.lookup(table, key) do
      [{^key, dump}] -> {:ok, dump}
      [] -> :not_found
    end
  rescue
    ArgumentError -> :not_found
  end

  @impl true
  def put(key, dump, opts) do
    table = Keyword.fetch!(opts, :table)
    ensure_table(table)
    :ets.insert(table, {key, dump})
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  def delete(key, opts) do
    table = Keyword.fetch!(opts, :table)
    ensure_table(table)
    :ets.delete(table, key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp ensure_table(table) do
    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [:named_table, :public, :set, read_concurrency: true])

      _ref ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
