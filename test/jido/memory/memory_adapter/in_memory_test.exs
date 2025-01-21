defmodule Jido.Memory.MemoryAdapter.InMemoryTest do
  use ExUnit.Case, async: true
  alias Jido.Memory.MemoryAdapter.InMemory
  alias Jido.Memory.Types.{Memory, KnowledgeItem}

  setup do
    {:ok, pid} = InMemory.init(name: :"test_#{:erlang.unique_integer()}")
    %{pid: pid}
  end

  describe "memory operations" do
    test "creates and retrieves a memory", %{pid: pid} do
      memory = %Memory{
        id: "test_mem",
        user_id: "user1",
        agent_id: "agent1",
        room_id: "room1",
        content: "test content",
        created_at: DateTime.utc_now()
      }

      assert {:ok, ^memory} = InMemory.create_memory(memory, pid)
      assert {:ok, ^memory} = InMemory.get_memory_by_id(memory.id, pid)
    end

    test "retrieves memories by room", %{pid: pid} do
      room_id = "room1"

      _memories =
        for i <- 1..3 do
          memory = %Memory{
            id: "mem_#{i}",
            user_id: "user1",
            agent_id: "agent1",
            room_id: if(i == 3, do: "other_room", else: room_id),
            content: "content #{i}",
            created_at: DateTime.utc_now()
          }

          {:ok, _} = InMemory.create_memory(memory, pid)
          memory
        end

      {:ok, room_memories} = InMemory.get_memories(room_id, [], pid)
      assert length(room_memories) == 2
      assert Enum.all?(room_memories, &(&1.room_id == room_id))
    end

    test "searches memories by embedding", %{pid: pid} do
      embedding1 = [1.0, 0.0, 0.0]
      embedding2 = [0.0, 1.0, 0.0]
      embedding3 = [0.9, 0.1, 0.0]

      embeddings = [embedding1, embedding2, embedding3]

      _memories =
        Enum.map(Enum.with_index(embeddings), fn {emb, i} ->
          memory = %Memory{
            id: "mem_#{i}",
            user_id: "user1",
            agent_id: "agent1",
            room_id: "room1",
            content: "content #{i}",
            created_at: DateTime.utc_now(),
            embedding: emb
          }

          {:ok, _} = InMemory.create_memory(memory, pid)
          memory
        end)

      query_embedding = [1.0, 0.0, 0.0]

      {:ok, results} =
        InMemory.search_memories_by_embedding(query_embedding, [threshold: 0.8], pid)

      assert length(results) == 2
      [first, second] = results
      # exact match
      assert first.id == "mem_0"
      # similar
      assert second.id == "mem_2"
      assert first.similarity > second.similarity
    end
  end

  describe "knowledge operations" do
    test "creates and searches knowledge items", %{pid: pid} do
      embedding1 = [1.0, 0.0, 0.0]
      embedding2 = [0.0, 1.0, 0.0]

      embeddings = [embedding1, embedding2]

      _items =
        Enum.map(Enum.with_index(embeddings), fn {emb, i} ->
          item = %KnowledgeItem{
            id: "ki_#{i}",
            agent_id: "agent1",
            content: "content #{i}",
            created_at: DateTime.utc_now(),
            embedding: emb
          }

          {:ok, _} = InMemory.create_knowledge(item, pid)
          item
        end)

      query_embedding = [0.9, 0.1, 0.0]

      {:ok, results} =
        InMemory.search_knowledge_by_embedding(query_embedding, [threshold: 0.8], pid)

      assert length(results) == 1
      [match] = results
      assert match.id == "ki_0"
      assert match.similarity > 0.8
    end
  end
end
