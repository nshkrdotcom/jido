defmodule Jido.Chat.RoomTest do
  use JidoTest.Case, async: true

  alias Jido.Chat.{Room, Message, Participant}

  defmodule TestRoom do
    use Jido.Chat.Room

    def mount(room) do
      send(test_process(), {:mount_called, room})
      {:ok, room}
    end

    def handle_message(room, message) do
      send(test_process(), {:handle_message_called, room, message})
      {:ok, message}
    end

    def handle_join(room, participant) do
      send(test_process(), {:handle_join_called, room, participant})
      {:ok, participant}
    end

    def handle_leave(room, participant) do
      send(test_process(), {:handle_leave_called, room, participant})
      {:ok, participant}
    end

    defp test_process, do: Process.whereis(RoomTest)
  end

  setup do
    # Register this test process to receive messages
    Process.register(self(), RoomTest)

    {:ok, room} = Room.start_link(bus_name: "test_bus", room_id: "room1", module: TestRoom)

    # Verify mount was called
    assert_receive {:mount_called, ^room}

    %{room: room}
  end

  describe "callbacks" do
    test "handle_join is called when adding participant", %{room: room} do
      participant = Participant.new!("user1", :human, display_name: "Bob")
      assert :ok = Room.add_participant(room, participant)
      assert_receive {:handle_join_called, ^room, ^participant}
    end

    test "handle_leave is called when removing participant", %{room: room} do
      participant = Participant.new!("user1", :human)
      :ok = Room.add_participant(room, participant)
      assert_receive {:handle_join_called, ^room, ^participant}

      assert :ok = Room.remove_participant(room, "user1")
      assert_receive {:handle_leave_called, ^room, ^participant}
    end

    test "handle_message is called when posting message", %{room: room} do
      {:ok, message} = Room.post_message(room, "Hello world", "agent_123")
      assert_receive {:handle_message_called, ^room, ^message}
    end
  end

  describe "add_participant/2" do
    test "adds a human participant to the room", %{room: room} do
      participant = Participant.new!("user1", :human, display_name: "Bob")
      assert :ok = Room.add_participant(room, participant)

      participants = Room.list_participants(room)
      assert length(participants) == 1
      assert hd(participants).id == "user1"
    end

    test "adds an agent participant to the room", %{room: room} do
      participant = Participant.new!("agent1", :agent)
      assert :ok = Room.add_participant(room, participant)

      participants = Room.list_participants(room)
      assert length(participants) == 1
      assert hd(participants).type == :agent
    end

    test "prevents duplicate participants", %{room: room} do
      participant = Participant.new!("user1", :human)
      assert :ok = Room.add_participant(room, participant)
      assert {:error, :already_joined} = Room.add_participant(room, participant)
    end
  end

  describe "remove_participant/2" do
    test "removes a participant from the room", %{room: room} do
      participant = Participant.new!("user1", :human)
      :ok = Room.add_participant(room, participant)
      assert :ok = Room.remove_participant(room, "user1")
      assert Room.list_participants(room) == []
    end

    test "returns error for unknown participant", %{room: room} do
      assert {:error, :not_found} = Room.remove_participant(room, "unknown")
    end
  end

  describe "list_participants/1" do
    test "returns all participants in the room", %{room: room} do
      human = Participant.new!("user1", :human, display_name: "Bob")
      agent = Participant.new!("agent1", :agent)

      :ok = Room.add_participant(room, human)
      :ok = Room.add_participant(room, agent)

      participants = Room.list_participants(room)
      assert length(participants) == 2
      assert Enum.any?(participants, &(&1.id == "user1"))
      assert Enum.any?(participants, &(&1.id == "agent1"))
    end

    test "returns empty list for empty room", %{room: room} do
      assert Room.list_participants(room) == []
    end
  end

  describe "post_message/4" do
    test "publishes text message to the bus", %{room: room} do
      {:ok, message} = Room.post_message(room, "Hello world", "agent_123")
      assert Message.type(message) == :text
      assert Message.content(message) == "Hello world"
      assert Message.sender_id(message) == "agent_123"
    end

    test "publishes rich message with payload", %{room: room} do
      payload = %{url: "https://example.com", mime_type: "image/png", size: 1024}

      {:ok, message} =
        Room.post_message(room, "Check this out", "agent_123", type: :rich, payload: payload)

      assert Message.type(message) == :rich
      assert Message.payload(message) == payload
    end

    test "publishes system message", %{room: room} do
      {:ok, message} = Room.post_message(room, "User joined", "system", type: :system)
      assert Message.type(message) == :system
      assert Message.content(message) == "User joined"
    end

    test "returns error for invalid message", %{room: room} do
      assert {:error, :content_required} = Room.post_message(room, "", "agent_123")
    end

    test "returns error for rich message without payload", %{room: room} do
      assert {:error, :payload_required} =
               Room.post_message(room, "Check this out", "agent_123", type: :rich)
    end

    test "supports threaded messages", %{room: room} do
      {:ok, parent} = Room.post_message(room, "Parent", "agent_123")

      {:ok, reply} =
        Room.post_message(room, "Reply", "agent_123", thread_id: Message.thread_id(parent))

      assert Message.thread_id(reply) == Message.thread_id(parent)
    end
  end

  describe "get_messages/1" do
    test "returns empty list when no messages", %{room: room} do
      assert {:ok, []} = Room.get_messages(room)
    end

    test "returns messages in chronological order", %{room: room} do
      {:ok, msg1} = Room.post_message(room, "First", "agent_123")
      {:ok, msg2} = Room.post_message(room, "Second", "agent_123")
      {:ok, messages} = Room.get_messages(room)
      assert length(messages) == 2
      assert [^msg1, ^msg2] = messages
    end

    test "returns messages of all types", %{room: room} do
      {:ok, _text} = Room.post_message(room, "Hello", "agent_123")

      {:ok, _rich} =
        Room.post_message(room, "Check this", "agent_123",
          type: :rich,
          payload: %{url: "https://example.com"}
        )

      {:ok, _system} = Room.post_message(room, "User joined", "system", type: :system)

      {:ok, messages} = Room.get_messages(room)
      assert length(messages) == 3
      assert Enum.any?(messages, &(Message.type(&1) == :text))
      assert Enum.any?(messages, &(Message.type(&1) == :rich))
      assert Enum.any?(messages, &(Message.type(&1) == :system))
    end
  end

  describe "get_thread/2" do
    test "returns all messages in a thread", %{room: room} do
      {:ok, parent} = Room.post_message(room, "Parent", "agent_123")
      thread_id = Message.thread_id(parent)
      {:ok, reply1} = Room.post_message(room, "Reply 1", "agent_123", thread_id: thread_id)
      {:ok, reply2} = Room.post_message(room, "Reply 2", "agent_123", thread_id: thread_id)

      {:ok, thread} = Room.get_thread(room, thread_id)
      assert length(thread) == 3
      assert parent in thread
      assert reply1 in thread
      assert reply2 in thread
    end

    test "returns error for invalid thread id", %{room: room} do
      assert {:error, :thread_not_found} = Room.get_thread(room, "invalid_id")
    end

    test "includes rich messages in thread", %{room: room} do
      {:ok, parent} = Room.post_message(room, "Parent", "agent_123")
      thread_id = Message.thread_id(parent)

      {:ok, rich_reply} =
        Room.post_message(room, "Rich reply", "agent_123",
          type: :rich,
          payload: %{url: "https://example.com"},
          thread_id: thread_id
        )

      {:ok, thread} = Room.get_thread(room, thread_id)
      assert length(thread) == 2
      assert rich_reply in thread
    end
  end
end
