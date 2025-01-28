defmodule Jido.Chat.Message do
  @moduledoc """
  Represents a chat message that wraps a Signal.
  """

  alias Jido.Chat.Message
  alias Jido.Signal

  @message_type_text "jido.chat.message.text"
  @message_type_rich "jido.chat.message.rich"
  @message_type_system "jido.chat.message.system"

  defstruct [:signal]

  @type t :: %__MODULE__{
          signal: Signal.t()
        }

  @doc """
  Creates a new text message.
  """
  def new(attrs) when is_map(attrs) do
    new(attrs, :text)
  end

  @doc """
  Creates a new rich or system message.
  """
  def new(attrs, type) when type in [:text, :rich, :system] do
    with {:ok, content} <- validate_content(attrs.content),
         {:ok, payload} <- validate_payload(type, attrs[:payload]) do
      signal_attrs = %{
        id: UUID.uuid4(),
        type: message_type(type),
        source: attrs[:source],
        subject: attrs[:sender_id],
        data: %{
          content: content,
          thread_id: attrs[:thread_id],
          mentions: parse_mentions(content, attrs[:participants] || %{}),
          payload: payload
        }
      }

      {:ok, %Message{signal: struct!(Signal, signal_attrs)}}
    end
  end

  @doc """
  Returns the content of the message.
  """
  def content(%Message{signal: signal}), do: signal.data.content

  @doc """
  Returns the sender ID of the message.
  """
  def sender_id(%Message{signal: signal}), do: signal.subject

  @doc """
  Returns the thread ID of the message, if any.
  """
  def thread_id(%Message{signal: signal}), do: signal.data.thread_id

  @doc """
  Returns the mentions in the message, if any.
  """
  def mentions(%Message{signal: signal}), do: signal.data.mentions

  @doc """
  Returns the payload of a rich message, if any.
  """
  def payload(%Message{signal: signal}) do
    case signal.type do
      @message_type_rich -> signal.data.payload
      _ -> nil
    end
  end

  @doc """
  Returns the type of the message (:text, :rich, or :system).
  """
  def type(%Message{signal: signal}) do
    case signal.type do
      @message_type_text -> :text
      @message_type_rich -> :rich
      @message_type_system -> :system
    end
  end

  defp message_type(:text), do: @message_type_text
  defp message_type(:rich), do: @message_type_rich
  defp message_type(:system), do: @message_type_system

  defp validate_content(nil), do: {:error, :content_required}
  defp validate_content(""), do: {:error, :content_required}
  defp validate_content(content) when is_binary(content), do: {:ok, content}

  defp validate_payload(:rich, nil), do: {:error, :payload_required}
  defp validate_payload(:rich, payload) when is_map(payload), do: {:ok, payload}
  defp validate_payload(_type, _), do: {:ok, nil}

  defp parse_mentions(content, participants) when is_map(participants) do
    case Jido.Chat.Message.Parser.parse_mentions(content, participants) do
      {:ok, mentions} -> mentions
      {:error, _} -> []
    end
  end
end
