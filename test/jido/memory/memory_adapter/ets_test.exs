defmodule Jido.Memory.MemoryAdapter.ETSTest do
  use ExUnit.Case, async: true
  alias Jido.Memory.MemoryAdapter.ETS
  alias Jido.Memory.Types.{Memory, KnowledgeItem}

  setup do
    table_name = :"test_#{:erlang.unique_integer()}"
    {:ok, table} = ETS.init(name: table_name)
    %{table: table}
  end

  describe "memory operations" do
    test "creates and retrieves a memory", %{table: table} do
      memory = %Memory{
        id: "test_mem",
        user_id: "user1",
        agent_id: "agent1",
        room_id: "room1",
        content: "test content",
        created_at: DateTime.utc_now()
      }

      assert {:ok, ^memory} = ETS.create_memory(memory, table)
      assert {:ok, ^memory} = ETS.get_memory_by_id(memory.id, table)
    end

    test "returns nil for non-existent memory", %{table: table} do
      assert {:ok, nil} = ETS.get_memory_by_id("non_existent", table)
    end

    test "retrieves memories by room", %{table: table} do
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

          {:ok, _} = ETS.create_memory(memory, table)
          memory
        end

      {:ok, room_memories} = ETS.get_memories(room_id, [], table)
      assert length(room_memories) == 2
      assert Enum.all?(room_memories, &(&1.room_id == room_id))
    end

    test "searches memories by embedding", %{table: table} do
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

          {:ok, _} = ETS.create_memory(memory, table)
          memory
        end)

      query_embedding = [1.0, 0.0, 0.0]

      {:ok, results} = ETS.search_memories_by_embedding(query_embedding, [threshold: 0.8], table)

      assert length(results) == 2
      [first, second] = results
      assert first.id == "mem_0"
      assert second.id == "mem_2"
      assert first.similarity > second.similarity
    end
  end

  describe "knowledge operations" do
    test "creates and searches knowledge items", %{table: table} do
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

          {:ok, _} = ETS.create_knowledge(item, table)
          item
        end)

      query_embedding = [0.9, 0.1, 0.0]

      {:ok, results} = ETS.search_knowledge_by_embedding(query_embedding, [threshold: 0.8], table)

      assert length(results) == 1
      [match] = results
      assert match.id == "ki_0"
      assert match.similarity > 0.8
    end

    test "handles concurrent operations safely", %{table: table} do
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            memory = %Memory{
              id: "mem_#{i}",
              user_id: "user1",
              agent_id: "agent1",
              room_id: "room1",
              content: "content #{i}",
              created_at: DateTime.utc_now()
            }

            {:ok, _} = ETS.create_memory(memory, table)
            {:ok, retrieved} = ETS.get_memory_by_id(memory.id, table)
            assert retrieved.id == memory.id
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      {:ok, all_memories} = ETS.get_memories("room1", [], table)
      assert length(all_memories) == 100
    end
  end
end
