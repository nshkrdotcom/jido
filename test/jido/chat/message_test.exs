defmodule Jido.Chat.MessageTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Message

  @participants %{
    "user1" => "bob",
    "user2" => "alice"
  }

  describe "new/1" do
    test "creates a text message with valid data" do
      attrs = %{
        content: "Hello world",
        sender_id: "sender1",
        room_id: "room1"
      }

      {:ok, message} = Message.new(attrs)
      assert Message.content(message) == "Hello world"
      assert Message.sender_id(message) == "sender1"
      assert Message.type(message) == :text
      assert Message.mentions(message) == []
    end

    test "creates a text message with mentions" do
      attrs = %{
        content: "Hey @bob and @alice!",
        sender_id: "sender1",
        room_id: "room1",
        participants: @participants
      }

      {:ok, message} = Message.new(attrs)
      mentions = Message.mentions(message)
      assert length(mentions) == 2

      [bob_ref, alice_ref] = mentions
      assert bob_ref.participant_id == "user1"
      assert alice_ref.participant_id == "user2"
    end

    test "returns error for empty content" do
      attrs = %{content: "", sender_id: "sender1", room_id: "room1"}
      assert {:error, :content_required} = Message.new(attrs)
    end

    test "returns error for nil content" do
      attrs = %{content: nil, sender_id: "sender1", room_id: "room1"}
      assert {:error, :content_required} = Message.new(attrs)
    end
  end

  describe "new/2" do
    test "creates a rich message with valid data" do
      attrs = %{
        content: "Check this out",
        sender_id: "sender1",
        room_id: "room1",
        payload: %{url: "https://example.com", mime_type: "image/png", size: 1024}
      }

      {:ok, message} = Message.new(attrs, :rich)
      assert Message.content(message) == "Check this out"
      assert Message.type(message) == :rich
      assert Message.payload(message) == attrs.payload
    end

    test "creates a rich message with mentions" do
      attrs = %{
        content: "Hey @bob, check this out!",
        sender_id: "sender1",
        room_id: "room1",
        payload: %{url: "https://example.com"},
        participants: @participants
      }

      {:ok, message} = Message.new(attrs, :rich)
      [mention] = Message.mentions(message)
      assert mention.participant_id == "user1"
      assert mention.display_name == "bob"
    end

    test "creates a system message" do
      attrs = %{
        content: "User joined the room",
        sender_id: "system",
        room_id: "room1"
      }

      {:ok, message} = Message.new(attrs, :system)
      assert Message.type(message) == :system
      assert Message.content(message) == "User joined the room"
    end
  end

  describe "thread_id/1" do
    test "returns thread ID when present" do
      attrs = %{
        content: "A reply",
        sender_id: "sender1",
        room_id: "room1",
        thread_id: "thread1"
      }

      {:ok, message} = Message.new(attrs)
      assert Message.thread_id(message) == "thread1"
    end

    test "returns nil when no thread ID" do
      attrs = %{
        content: "No thread",
        sender_id: "sender1",
        room_id: "room1"
      }

      {:ok, message} = Message.new(attrs)
      assert Message.thread_id(message) == nil
    end
  end
end
