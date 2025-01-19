defmodule Jido.Chat.Message.Parser do
  @moduledoc """
  Parser for chat messages using NimbleParsec.
  """

  import NimbleParsec

  defmodule Mention do
    @type t :: %__MODULE__{
            participant_id: String.t(),
            display_name: String.t(),
            offset: non_neg_integer(),
            length: non_neg_integer()
          }
    defstruct [:participant_id, :display_name, :offset, :length]
  end

  # Basic parsec building blocks
  whitespace = ascii_string([?\s, ?\t, ?\n, ?\r], min: 1)
  mention_char = ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])

  # Define the mention_name combinator
  mention_name_parser =
    ignore(ascii_char([?@]))
    |> repeat(mention_char)
    |> reduce({List, :to_string, []})
    |> post_traverse({:track_offset, []})

  defcombinator(:mention_name, mention_name_parser)

  # Define the content parser
  content_parser =
    repeat(
      choice([
        parsec(:mention_name),
        ignore(whitespace),
        utf8_string([], 1)
      ])
    )

  defparsecp(:parse_content, content_parser)

  @doc """
  Parse mentions from content.

  Returns a list of mention structs containing:
  - participant_id: The ID of the mentioned participant
  - display_name: The display name used in the mention
  - offset: The character offset where the mention starts
  - length: The length of the mention text
  """
  @spec parse_mentions(String.t(), %{String.t() => String.t()}) ::
          {:ok, [Mention.t()]} | {:error, term()}
  def parse_mentions(content, participants) when is_binary(content) and is_map(participants) do
    case parse_content(content) do
      {:ok, tokens, "", _, _, _} ->
        mentions =
          tokens
          |> Enum.filter(&is_tuple/1)
          |> Enum.flat_map(fn {name, offset} ->
            case find_participant(name, participants) do
              nil ->
                []

              {id, display_name} ->
                [
                  %Mention{
                    participant_id: id,
                    display_name: display_name,
                    offset: offset,
                    length: String.length(name)
                  }
                ]
            end
          end)

        {:ok, mentions}

      {:error, reason, _, _, _, _} ->
        {:error, reason}
    end
  end

  def parse_mentions(_content, _participants), do: {:error, :invalid_input}

  # Helpers

  defp find_participant(name, participants) do
    Enum.find(participants, fn {_id, display_name} ->
      String.downcase(display_name) == String.downcase(name)
    end)
  end

  # NimbleParsec callbacks

  defp track_offset(_rest, [name], context, _line, offset) do
    {[{name, offset - String.length(name) - 1}], context}
  end
end
