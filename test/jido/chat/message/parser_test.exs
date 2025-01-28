defmodule Jido.Chat.Message.ParserTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Message.Parser

  @participants %{
    "user1" => "bob",
    "user2" => "alice",
    "user3" => "charlie"
  }

  describe "parse_mentions/2" do
    test "extracts mentions from content" do
      content = "Hey @bob and @alice, how are you?"
      {:ok, mentions} = Parser.parse_mentions(content, @participants)

      assert length(mentions) == 2

      [bob_ref, alice_ref] = mentions

      assert bob_ref.participant_id == "user1"
      assert bob_ref.display_name == "bob"
      assert bob_ref.offset == 4
      assert bob_ref.length == 3

      assert alice_ref.participant_id == "user2"
      assert alice_ref.display_name == "alice"
      assert alice_ref.offset == 13
      assert alice_ref.length == 5
    end

    test "handles content with no mentions" do
      content = "Hello everyone!"
      {:ok, mentions} = Parser.parse_mentions(content, @participants)
      assert mentions == []
    end

    test "handles multiple mentions of the same participant" do
      content = "@bob hey @bob"
      {:ok, mentions} = Parser.parse_mentions(content, @participants)

      assert length(mentions) == 2
      [first, second] = mentions
      assert first.participant_id == "user1"
      assert first.offset == 0
      assert first.length == 3
      assert second.participant_id == "user1"
      assert second.offset == 9
      assert second.length == 3
    end

    test "ignores mentions of unknown participants" do
      content = "@bob and @unknown"
      {:ok, mentions} = Parser.parse_mentions(content, @participants)

      assert length(mentions) == 1
      mention = hd(mentions)
      assert mention.participant_id == "user1"
      assert mention.offset == 0
      assert mention.length == 3
    end

    test "handles case-insensitive matching" do
      content = "@BOB and @Alice"
      {:ok, mentions} = Parser.parse_mentions(content, @participants)

      assert length(mentions) == 2
      [bob_ref, alice_ref] = mentions
      assert bob_ref.participant_id == "user1"
      assert bob_ref.offset == 0
      assert bob_ref.length == 3
      assert alice_ref.participant_id == "user2"
      assert alice_ref.offset == 9
      assert alice_ref.length == 5
    end

    test "returns error for invalid input" do
      assert {:error, :invalid_input} = Parser.parse_mentions(nil, @participants)
      assert {:error, :invalid_input} = Parser.parse_mentions("test", nil)
    end
  end
end
