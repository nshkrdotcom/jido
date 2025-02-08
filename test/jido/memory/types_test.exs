defmodule Jido.Memory.TypesTest do
  use JidoTest.Case, async: true
  alias Jido.Memory.Types.{Memory, KnowledgeItem}

  describe "Memory struct" do
    test "creates a memory with required fields" do
      memory = %Memory{
        id: "mem_123",
        user_id: "user1",
        agent_id: "agent1",
        room_id: "room1",
        content: "test content",
        created_at: DateTime.utc_now()
      }

      assert %Memory{} = memory
      assert memory.id == "mem_123"
      # default value
      assert memory.unique == false
      # default value
      assert is_nil(memory.similarity)
    end

    test "raises error when missing required fields" do
      message =
        "the following keys must also be given when building struct Jido.Memory.Types.Memory: " <>
          "[:user_id, :agent_id, :room_id, :content, :created_at]"

      assert_raise ArgumentError, message, fn ->
        struct!(Memory, id: "mem_123")
      end
    end
  end

  describe "KnowledgeItem struct" do
    test "creates a knowledge item with required fields" do
      item = %KnowledgeItem{
        id: "ki_123",
        agent_id: "agent1",
        content: "test content",
        created_at: DateTime.utc_now()
      }

      assert %KnowledgeItem{} = item
      assert item.id == "ki_123"
      # default value
      assert is_nil(item.similarity)
    end

    test "raises error when missing required fields" do
      message =
        "the following keys must also be given when building struct Jido.Memory.Types.KnowledgeItem: " <>
          "[:agent_id, :content, :created_at]"

      assert_raise ArgumentError, message, fn ->
        struct!(KnowledgeItem, id: "ki_123")
      end
    end
  end
end
