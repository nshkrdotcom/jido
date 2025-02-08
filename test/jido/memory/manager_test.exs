defmodule Jido.Memory.ManagerTest do
  use JidoTest.Case, async: true
  alias Jido.Memory.{Manager, Types.Memory}
  import Jido.Memory.TestHelpers

  setup do
    cleanup_ets_tables()
    name = :"test_#{:erlang.unique_integer()}"
    memory_table = :"#{name}_memories"
    knowledge_table = :"#{name}_knowledge"

    # Clean up any existing tables
    if :ets.whereis(memory_table) != :undefined, do: :ets.delete(memory_table)
    if :ets.whereis(knowledge_table) != :undefined, do: :ets.delete(knowledge_table)

    {:ok, pid} = Manager.start_link(adapter: Jido.Memory.MemoryAdapter.ETS, name: name)
    %{pid: pid}
  end

  describe "memory operations" do
    test "creates and retrieves a memory", %{pid: pid} do
      params = %{
        user_id: "user1",
        agent_id: "agent1",
        room_id: "room1",
        content: "test content"
      }

      assert {:ok, %Memory{} = memory} = Manager.create_memory(pid, params)
      assert memory.user_id == params.user_id
      assert memory.agent_id == params.agent_id
      assert memory.room_id == params.room_id
      assert memory.content == params.content
      assert memory.id != nil
      assert memory.created_at != nil

      assert {:ok, ^memory} = Manager.get_memory_by_id(pid, memory.id)
    end

    test "returns error for invalid memory params", %{pid: pid} do
      assert {:error, :invalid_params} = Manager.create_memory(pid, %{})
    end

    test "retrieves memories by room", %{pid: pid} do
      room_id = "room1"

      # Create some test memories
      _memories =
        for i <- 1..3 do
          params = %{
            user_id: "user1",
            agent_id: "agent1",
            room_id: if(i == 3, do: "other_room", else: room_id),
            content: "content #{i}"
          }

          {:ok, memory} = Manager.create_memory(pid, params)
          memory
        end

      {:ok, room_memories} = Manager.get_memories(pid, room_id)
      assert length(room_memories) == 2
      assert Enum.all?(room_memories, &(&1.room_id == room_id))
    end

    test "searches memories by content similarity", %{pid: pid} do
      # Create test memories with embeddings
      _memories =
        for {content, embedding} <- [
              {"The quick brown fox", [1.0, 0.0, 0.0]},
              {"A lazy dog sleeps", [0.0, 1.0, 0.0]},
              {"The fast brown fox runs", [0.9, 0.1, 0.0]}
            ] do
          params = %{
            user_id: "user1",
            agent_id: "agent1",
            room_id: "room1",
            content: content,
            embedding: embedding
          }

          {:ok, memory} = Manager.create_memory(pid, params)
          memory
        end

      query = "quick brown fox"
      # Simulated embedding
      query_embedding = [1.0, 0.0, 0.0]

      {:ok, results} = Manager.search_similar_memories(pid, query, query_embedding)

      assert length(results) == 2
      [first, second] = results
      assert first.content == "The quick brown fox"
      assert second.content == "The fast brown fox runs"
      assert first.similarity > second.similarity
    end

    test "handles concurrent operations", %{pid: pid} do
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            params = %{
              user_id: "user1",
              agent_id: "agent1",
              room_id: "room1",
              content: "content #{i}"
            }

            {:ok, memory} = Manager.create_memory(pid, params)
            {:ok, retrieved} = Manager.get_memory_by_id(pid, memory.id)
            assert retrieved.id == memory.id
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      {:ok, all_memories} = Manager.get_memories(pid, "room1")
      assert length(all_memories) == 100
    end
  end

  describe "configuration" do
    test "starts with default adapter" do
      {:ok, pid} = Manager.start_link(name: :"default_#{:erlang.unique_integer()}")
      assert Process.alive?(pid)
    end

    test "starts with custom adapter" do
      {:ok, pid} =
        Manager.start_link(
          adapter: Jido.Memory.MemoryAdapter.InMemory,
          name: :"custom_#{:erlang.unique_integer()}"
        )

      assert Process.alive?(pid)
    end

    test "returns error for invalid adapter" do
      Process.flag(:trap_exit, true)
      assert {:error, {:invalid_adapter, _}} = Manager.start_link(adapter: InvalidAdapter)
    end
  end
end
