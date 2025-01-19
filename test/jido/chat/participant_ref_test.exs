defmodule Jido.Chat.ParticipantRefTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.ParticipantRef

  describe "new/4" do
    test "creates a new participant reference with valid data" do
      ref = ParticipantRef.new("user123", "bob", 0, 4)
      assert ref.participant_id == "user123"
      assert ref.display_name == "bob"
      assert ref.ref_type == :mention
      assert ref.offset == 0
      assert ref.length == 4
    end
  end
end
