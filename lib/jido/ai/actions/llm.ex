defmodule Jido.AI.Actions.LLM do
  @moduledoc """
  Provides text generation and chat completion using LLMs.
  """

  alias Jido.AI.Models.Registry

  @type generation_result :: {:ok, String.t()} | {:error, String.t()}
  @type stream_result :: Stream.t()
  @type message :: %{role: String.t(), content: String.t()}

  @doc """
  Generates text using the specified provider and settings.
  """
  @spec generate_text(String.t(), keyword()) :: generation_result()
  def generate_text("", _opts), do: {:error, "Prompt cannot be empty"}

  def generate_text(prompt, opts) do
    with {:ok, _provider} <- validate_provider(opts),
         {:ok, _settings} <- validate_generation_params(opts) do
      # TODO: Implement actual provider call
      {:ok, "Generated text for: #{prompt}"}
    end
  end

  @doc """
  Streams text generation using the specified provider and settings.
  """
  @spec stream_text(String.t(), keyword()) :: stream_result()
  def stream_text(prompt, opts) do
    case validate_streaming_setup(prompt, opts) do
      {:ok, _state} ->
        1..5
        |> Stream.map(fn i ->
          if i == 5 do
            {:ok, "Final chunk for: #{prompt}"}
          else
            {:ok, "Chunk #{i}"}
          end
        end)

      {:error, message} ->
        Stream.map([{:error, message}], & &1)
    end
  end

  @doc """
  Generates chat completion using the specified provider and settings.
  """
  @spec chat(message(), keyword()) :: generation_result()
  def chat([], _opts), do: {:error, "Messages cannot be empty"}

  def chat(messages, opts) do
    with :ok <- validate_messages(messages),
         {:ok, _provider} <- validate_provider(opts),
         {:ok, _settings} <- validate_generation_params(opts) do
      # TODO: Implement actual provider call
      {:ok, "Chat response for: #{inspect(messages)}"}
    end
  end

  @doc """
  Streams chat completion using the specified provider and settings.
  """
  @spec stream_chat([message()], keyword()) :: stream_result()
  def stream_chat(messages, opts) do
    case validate_streaming_setup(messages, opts) do
      {:ok, _state} ->
        1..5
        |> Stream.map(fn i ->
          if i == 5 do
            {:ok, "Final chat chunk for: #{inspect(messages)}"}
          else
            {:ok, "Chat chunk #{i}"}
          end
        end)

      {:error, message} ->
        Stream.map([{:error, message}], & &1)
    end
  end

  # Private functions

  defp validate_provider(opts) do
    case Keyword.get(opts, :provider) do
      nil ->
        {:error, "Provider is required"}

      provider ->
        case Registry.get_provider(provider) do
          nil -> {:error, "Provider not found"}
          config -> {:ok, config}
        end
    end
  end

  defp validate_generation_params(opts) do
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    cond do
      not is_float(temperature) or temperature < 0.0 or temperature > 1.0 ->
        {:error, "Temperature must be between 0.0 and 1.0"}

      not is_integer(max_tokens) or max_tokens < 1 ->
        {:error, "tokens must be positive"}

      true ->
        {:ok, %{temperature: temperature, max_tokens: max_tokens}}
    end
  end

  defp validate_messages([]), do: {:error, "Messages cannot be empty"}

  defp validate_messages(messages) do
    if Enum.all?(messages, &valid_message?/1) do
      :ok
    else
      {:error, "Invalid message role"}
    end
  end

  defp valid_message?(%{role: role, content: content})
       when is_binary(role) and is_binary(content) and role in ["user", "assistant", "system"],
       do: true

  defp valid_message?(_), do: false

  defp validate_streaming_setup(input, opts) do
    with {:ok, provider} <- validate_provider(opts),
         {:ok, settings} <- validate_generation_params(opts) do
      {:ok,
       %{
         input: input,
         provider: provider,
         settings: settings,
         chunks_sent: 0
       }}
    end
  end
end
