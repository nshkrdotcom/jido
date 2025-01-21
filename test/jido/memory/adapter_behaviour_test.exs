defmodule Jido.Memory.AdapterBehaviourTest do
  use ExUnit.Case, async: true
  alias Jido.Memory.Types.{Memory, KnowledgeItem}

  # Define a mock adapter that implements the behaviour
  defmodule MockAdapter do
    @behaviour Jido.Memory.AdapterBehaviour

    def init(_opts), do: {:ok, %{}}

    def create_memory(%Memory{} = memory, _state), do: {:ok, memory}

    def get_memory_by_id(_id, _state), do: {:ok, nil}

    def get_memories(_room_id, _opts, _state), do: {:ok, []}

    def search_memories_by_embedding(_embedding, _opts, _state), do: {:ok, []}

    def create_knowledge(%KnowledgeItem{} = item, _state), do: {:ok, item}

    def search_knowledge_by_embedding(_embedding, _opts, _state), do: {:ok, []}
  end

  test "adapter behaviour requires all callback functions" do
    # Get all callbacks from the behaviour
    callbacks = Jido.Memory.AdapterBehaviour.behaviour_info(:callbacks)

    # Verify each callback exists in our mock adapter
    for {callback_name, arity} <- callbacks do
      assert function_exported?(MockAdapter, callback_name, arity),
             "#{callback_name}/#{arity} callback not implemented"
    end
  end

  test "init callback returns expected format" do
    assert {:ok, _state} = MockAdapter.init([])
  end

  test "create_memory callback returns expected format" do
    memory = %Memory{
      id: "test",
      user_id: "user1",
      agent_id: "agent1",
      room_id: "room1",
      content: "test",
      created_at: DateTime.utc_now()
    }

    assert {:ok, %Memory{}} = MockAdapter.create_memory(memory, %{})
  end

  test "create_knowledge callback returns expected format" do
    item = %KnowledgeItem{
      id: "test",
      agent_id: "agent1",
      content: "test",
      created_at: DateTime.utc_now()
    }

    assert {:ok, %KnowledgeItem{}} = MockAdapter.create_knowledge(item, %{})
  end
end
