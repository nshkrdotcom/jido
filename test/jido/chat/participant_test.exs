defmodule Jido.Chat.ParticipantTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Participant

  describe "new/2" do
    test "creates a human participant" do
      {:ok, participant} = Participant.new("user123", :human)
      assert participant.id == "user123"
      assert participant.type == :human
    end

    test "creates an agent participant" do
      {:ok, participant} = Participant.new("agent123", :agent)
      assert participant.id == "agent123"
      assert participant.type == :agent
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_type} = Participant.new("user123", :invalid)
    end
  end

  describe "display_name/1" do
    test "returns display name for human" do
      {:ok, participant} = Participant.new("user123", :human, display_name: "Bob")
      assert Participant.display_name(participant) == "Bob"
    end

    test "returns ID if no display name set" do
      {:ok, participant} = Participant.new("user123", :human)
      assert Participant.display_name(participant) == "user123"
    end
  end

  describe "type?/2" do
    test "returns true when type matches" do
      {:ok, participant} = Participant.new("user123", :human)
      assert Participant.type?(participant, :human)
      refute Participant.type?(participant, :agent)
    end
  end
end
