defmodule Jido.Chat.ParticipantRef do
  @moduledoc """
  Represents a reference to a participant within a message, such as an @mention.
  Stores both the participant information and the location of the reference in the message.
  """

  @type t :: %__MODULE__{
          participant_id: String.t(),
          display_name: String.t(),
          ref_type: :mention,
          offset: non_neg_integer(),
          length: pos_integer()
        }

  defstruct [:participant_id, :display_name, :ref_type, :offset, :length]

  @doc """
  Creates a new participant reference.

  ## Parameters
    * participant_id - The ID of the referenced participant
    * display_name - The display name used in the reference (e.g., "bob" in "@bob")
    * offset - The character offset in the message where the reference starts
    * length - The length of the reference in characters
  """
  def new(participant_id, display_name, offset, length) do
    %__MODULE__{
      participant_id: participant_id,
      display_name: display_name,
      ref_type: :mention,
      offset: offset,
      length: length
    }
  end
end
