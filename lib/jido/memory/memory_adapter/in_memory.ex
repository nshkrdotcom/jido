defmodule Jido.Memory.MemoryAdapter.InMemory do
  @moduledoc """
  In-memory implementation of the Memory adapter using Agent for state management.
  Primarily used for testing and development.
  """

  @behaviour Jido.Memory.AdapterBehaviour

  alias Jido.Memory.Types.{Memory, KnowledgeItem}

  defmodule State do
    @moduledoc false
    defstruct memories: %{}, knowledge_items: %{}
  end

  @impl true
  def init(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    case Agent.start_link(fn -> %State{} end, name: name) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @impl true
  def create_memory(%Memory{} = memory, pid) do
    Agent.update(pid, fn state ->
      %{state | memories: Map.put(state.memories, memory.id, memory)}
    end)

    {:ok, memory}
  end

  @impl true
  def get_memory_by_id(memory_id, pid) do
    memory = Agent.get(pid, fn state -> Map.get(state.memories, memory_id) end)
    {:ok, memory}
  end

  @impl true
  def get_memories(room_id, _opts, pid) do
    memories =
      Agent.get(pid, fn state ->
        state.memories
        |> Map.values()
        |> Enum.filter(&(&1.room_id == room_id))
      end)

    {:ok, memories}
  end

  @impl true
  def search_memories_by_embedding(embedding, opts, pid) do
    threshold = Keyword.get(opts, :threshold, 0.8)

    memories =
      Agent.get(pid, fn state ->
        state.memories
        |> Map.values()
        |> Enum.filter(&(&1.embedding != nil))
        |> Enum.map(fn memory ->
          similarity = cosine_similarity(memory.embedding, embedding)
          %{memory | similarity: similarity}
        end)
        |> Enum.filter(&(&1.similarity >= threshold))
        |> Enum.sort_by(fn item -> item.similarity end, :desc)
      end)

    {:ok, memories}
  end

  @impl true
  def create_knowledge(%KnowledgeItem{} = item, pid) do
    Agent.update(pid, fn state ->
      %{state | knowledge_items: Map.put(state.knowledge_items, item.id, item)}
    end)

    {:ok, item}
  end

  @impl true
  def search_knowledge_by_embedding(embedding, opts, pid) do
    threshold = Keyword.get(opts, :threshold, 0.8)

    items =
      Agent.get(pid, fn state ->
        state.knowledge_items
        |> Map.values()
        |> Enum.filter(&(&1.embedding != nil))
        |> Enum.map(fn item ->
          similarity = cosine_similarity(item.embedding, embedding)
          %{item | similarity: similarity}
        end)
        |> Enum.filter(&(&1.similarity >= threshold))
        |> Enum.sort_by(fn item -> item.similarity end, :desc)
      end)

    {:ok, items}
  end

  # Helper function to compute cosine similarity between two vectors
  defp cosine_similarity(v1, v2) when length(v1) == length(v2) do
    dot_product = Enum.zip_with(v1, v2, &(&1 * &2)) |> Enum.sum()
    magnitude1 = :math.sqrt(Enum.sum(Enum.map(v1, fn x -> x * x end)))
    magnitude2 = :math.sqrt(Enum.sum(Enum.map(v2, fn x -> x * x end)))

    case {magnitude1, magnitude2} do
      {magnitude, _} when magnitude == +0.0 -> +0.0
      {_, magnitude} when magnitude == +0.0 -> +0.0
      {m1, m2} -> dot_product / (m1 * m2)
    end
  end

  defp cosine_similarity(_, _), do: +0.0
end
