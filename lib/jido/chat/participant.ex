defmodule Jido.Chat.Participant do
  @moduledoc """
  Represents a participant in a chat room, which can be either a human user or an agent.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          type: :human | :agent,
          display_name: String.t() | nil
        }

  defstruct [:id, :type, :display_name]

  @valid_types [:human, :agent]

  @doc """
  Creates a new participant with the given ID and type.

  ## Options
    * :display_name - Optional display name for the participant

  ## Examples
      iex> Participant.new("user123", :human, display_name: "Bob")
      %Participant{id: "user123", type: :human, display_name: "Bob"}

      iex> Participant.new("agent123", :agent)
      %Participant{id: "agent123", type: :agent, display_name: nil}
  """
  def new(id, type, opts \\ []) when is_binary(id) do
    if type in @valid_types do
      %__MODULE__{
        id: id,
        type: type,
        display_name: Keyword.get(opts, :display_name)
      }
    else
      {:error, :invalid_type}
    end
  end

  @doc """
  Returns the display name of the participant, falling back to ID if not set.
  """
  def display_name(%__MODULE__{display_name: nil, id: id}), do: id
  def display_name(%__MODULE__{display_name: name}), do: name

  @doc """
  Returns true if the participant is of the given type.
  """
  def type?(%__MODULE__{type: type}, expected_type), do: type == expected_type
end
