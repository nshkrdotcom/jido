defmodule Jido.Memory.MemoryAdapter.ETS do
  @moduledoc """
  ETS-based adapter for storing knowledge items.
  """

  @behaviour Jido.Memory.AdapterBehaviour

  alias Jido.Memory.Types.{Memory, KnowledgeItem}

  @memory_table_suffix "_memories"
  @knowledge_table_suffix "_knowledge"

  @impl true
  def init(opts \\ []) do
    base_name = Keyword.get(opts, :name, __MODULE__)
    memory_table = :"#{base_name}#{@memory_table_suffix}"
    knowledge_table = :"#{base_name}#{@knowledge_table_suffix}"

    # Try to create the tables, if they don't exist
    with {:ok, memory_tab} <- ensure_table(memory_table),
         {:ok, knowledge_tab} <- ensure_table(knowledge_table) do
      {:ok, %{memory_table: memory_tab, knowledge_table: knowledge_tab}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined ->
        try do
          :ets.new(name, [:set, :public, :named_table])
          {:ok, name}
        rescue
          ArgumentError -> {:error, :table_exists}
        end

      _table ->
        {:ok, name}
    end
  end

  @impl true
  def create_memory(%Memory{} = memory, %{memory_table: table}) do
    true = :ets.insert(table, {memory.id, memory})
    {:ok, memory}
  end

  @impl true
  def get_memory_by_id(memory_id, %{memory_table: table}) do
    case :ets.lookup(table, memory_id) do
      [{^memory_id, memory}] -> {:ok, memory}
      [] -> {:ok, nil}
    end
  end

  @impl true
  def get_memories(room_id, _opts, %{memory_table: table}) do
    memories =
      :ets.tab2list(table)
      |> Enum.map(fn {_id, memory} -> memory end)
      |> Enum.filter(&(&1.room_id == room_id))

    {:ok, memories}
  end

  @impl true
  def search_memories_by_embedding(embedding, opts, %{memory_table: table}) do
    threshold = Keyword.get(opts, :threshold, 0.8)

    memories =
      :ets.tab2list(table)
      |> Enum.map(fn {_id, memory} -> memory end)
      |> Enum.filter(&(&1.embedding != nil))
      |> Enum.map(fn memory ->
        similarity = calculate_similarity(memory.embedding, embedding)
        %{memory | similarity: similarity}
      end)
      |> Enum.filter(&(&1.similarity >= threshold))
      |> Enum.sort_by(fn memory -> memory.similarity end, :desc)

    {:ok, memories}
  end

  @impl true
  def create_knowledge(%KnowledgeItem{} = item, %{knowledge_table: table}) do
    true = :ets.insert(table, {item.id, item})
    {:ok, item}
  end

  @impl true
  def search_knowledge_by_embedding(query_embedding, opts, %{knowledge_table: table}) do
    threshold = Keyword.get(opts, :threshold, 0.8)

    items =
      :ets.tab2list(table)
      |> Enum.map(fn {_, item} ->
        similarity = calculate_similarity(item.embedding, query_embedding)
        %{item | similarity: similarity}
      end)
      |> Enum.filter(&(&1.similarity >= threshold))
      |> Enum.sort_by(& &1.similarity, :desc)

    {:ok, items}
  end

  defp calculate_similarity(embedding1, embedding2) do
    case {embedding1, embedding2} do
      {nil, _} ->
        0.0

      {_, nil} ->
        0.0

      {e1, e2} ->
        # For testing purposes, we'll just use a simple dot product
        Enum.zip(e1, e2)
        |> Enum.map(fn {a, b} -> a * b end)
        |> Enum.sum()
    end
  end
end
