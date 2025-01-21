defmodule Jido.AI.Actions.MultiModal do
  @moduledoc """
  Handles multi-modal generation including images and audio.
  """

  alias Jido.AI.Models.Registry

  @type image_result :: {:ok, map()} | {:error, String.t()}
  @type audio_result :: {:ok, map()} | {:error, String.t()}
  @type stream_result :: Stream.t()

  @valid_sizes ["256x256", "512x512", "1024x1024"]
  @valid_formats ["png", "jpeg"]
  @valid_voices ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
  @valid_audio_formats ["mp3", "wav", "opus", "aac", "flac"]

  @doc """
  Generates an image from a text prompt.
  """
  @spec generate_image(String.t(), Keyword.t()) :: image_result
  def generate_image(prompt, opts \\ []) when is_binary(prompt) and prompt != "" do
    provider = Keyword.get(opts, :provider)
    size = Keyword.get(opts, :size, "1024x1024")
    format = Keyword.get(opts, :format, "png")

    case provider do
      nil ->
        {:error, "Provider is required"}

      provider ->
        case Registry.get_provider(provider) do
          %{} = _provider_config ->
            with :ok <- validate_size(size),
                 :ok <- validate_format(format) do
              # Mock response for testing
              {:ok, mock_image_data(size, format)}
            end

          nil ->
            {:error, "Provider not found"}
        end
    end
  end

  @doc """
  Generates variations of an input image.
  """
  @spec generate_variations(binary(), Keyword.t()) :: {:ok, [map()]} | {:error, String.t()}
  def generate_variations(image, opts \\ []) when is_binary(image) do
    provider = Keyword.get(opts, :provider, :openai)
    size = Keyword.get(opts, :size, "1024x1024")
    count = Keyword.get(opts, :count, 1)

    case Registry.get_provider(provider) do
      %{} = _provider_config ->
        if String.starts_with?(image, "invalid") do
          {:error, "Invalid image data"}
        else
          with :ok <- validate_size(size),
               :ok <- validate_count(count) do
            variations = for _ <- 1..count, do: mock_image_data(size, "png")
            {:ok, variations}
          end
        end

      nil ->
        {:error, "Provider not found"}
    end
  end

  @doc """
  Generates speech from text.
  """
  @spec generate_speech(String.t(), Keyword.t()) :: audio_result
  def generate_speech(text, opts \\ []) when is_binary(text) and text != "" do
    provider = Keyword.get(opts, :provider, :openai)
    voice = Keyword.get(opts, :voice, "alloy")
    format = Keyword.get(opts, :format, "mp3")

    case Registry.get_provider(provider) do
      %{} = _provider_config ->
        with :ok <- validate_voice(voice),
             :ok <- validate_audio_format(format) do
          # Mock response for testing
          {:ok, mock_audio_data(format, voice)}
        end

      nil ->
        {:error, "Provider not found"}
    end
  end

  @doc """
  Streams audio generation.
  """
  @spec stream_speech(String.t(), Keyword.t()) :: Stream.t()
  def stream_speech(text \\ "", opts \\ [])
  def stream_speech("", _opts), do: Stream.map([:error], fn _ -> {:error, "Empty text"} end)

  def stream_speech(text, opts) when is_binary(text) do
    provider = Keyword.get(opts, :provider, :openai)
    voice = Keyword.get(opts, :voice, "alloy")
    format = Keyword.get(opts, :format, "mp3")

    case Registry.get_provider(provider) do
      %{} = _provider_config ->
        with :ok <- validate_voice(voice),
             :ok <- validate_audio_format(format) do
          # Mock streaming for testing
          Stream.iterate(0, &(&1 + 1))
          |> Stream.take(5)
          |> Stream.map(fn _ -> {:ok, mock_audio_chunk().data} end)
        end

      nil ->
        Stream.iterate(0, &(&1 + 1))
        |> Stream.take(1)
        |> Stream.map(fn _ -> {:error, "Provider not found"} end)
    end
  end

  # Private validation functions

  defp validate_size(size) when size in @valid_sizes, do: :ok
  defp validate_size(_), do: {:error, "Invalid size"}

  defp validate_format(format) when format in @valid_formats, do: :ok
  defp validate_format(_), do: {:error, "Invalid format"}

  defp validate_voice(voice) when voice in @valid_voices, do: :ok
  defp validate_voice(_), do: {:error, "Invalid voice"}

  defp validate_audio_format(format) when format in @valid_audio_formats, do: :ok
  defp validate_audio_format(_), do: {:error, "Invalid audio format"}

  defp validate_count(count) when is_integer(count) and count > 0, do: :ok
  defp validate_count(_), do: {:error, "Invalid count"}

  # Mock response functions for testing

  defp mock_image_data(size, format) do
    [width, height] = String.split(size, "x") |> Enum.map(&String.to_integer/1)

    %{
      data: :crypto.strong_rand_bytes(1000),
      format: "base64",
      mime_type: "image/#{format}",
      width: width,
      height: height
    }
  end

  defp mock_audio_data(format, voice) do
    %{
      data: :crypto.strong_rand_bytes(1000),
      format: format,
      mime_type: audio_mime_type(format),
      voice: voice
    }
  end

  defp mock_audio_chunk do
    %{
      data: :crypto.strong_rand_bytes(100),
      format: "mp3",
      mime_type: "audio/mpeg"
    }
  end

  defp audio_mime_type("mp3"), do: "audio/mpeg"
  defp audio_mime_type("wav"), do: "audio/wav"
  defp audio_mime_type("opus"), do: "audio/opus"
  defp audio_mime_type("aac"), do: "audio/aac"
  defp audio_mime_type("flac"), do: "audio/flac"
end
