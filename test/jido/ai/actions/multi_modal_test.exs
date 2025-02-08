defmodule Jido.AI.Actions.MultiModalTest do
  use JidoTest.Case, async: true

  alias Jido.AI.Actions.MultiModal

  describe "image_generation" do
    test "generates image from prompt" do
      result = MultiModal.generate_image("A beautiful sunset", provider: :openai)
      assert {:ok, image} = result
      assert is_binary(image.data)
      assert image.format == "base64"
      assert image.mime_type == "image/png"
    end

    test "supports different image sizes" do
      result = MultiModal.generate_image("A cat", provider: :openai, size: "1024x1024")
      assert {:ok, image} = result
      assert image.width == 1024
      assert image.height == 1024
    end

    test "supports different image formats" do
      result = MultiModal.generate_image("A dog", provider: :openai, format: "jpeg")
      assert {:ok, image} = result
      assert image.mime_type == "image/jpeg"
    end

    test "handles invalid size" do
      result = MultiModal.generate_image("A bird", provider: :openai, size: "invalid")
      assert {:error, message} = result
      assert message =~ "Invalid size"
    end

    test "handles missing provider" do
      result = MultiModal.generate_image("A fish", [])
      assert {:error, message} = result
      assert message =~ "Provider is required"
    end
  end

  describe "image_variation" do
    test "generates variations of an image" do
      {:ok, original} = MultiModal.generate_image("A simple logo", provider: :openai)
      result = MultiModal.generate_variations(original.data, count: 2, provider: :openai)

      assert {:ok, variations} = result
      assert length(variations) == 2
      assert Enum.all?(variations, &is_binary(&1.data))
      assert Enum.all?(variations, &(&1.format == "base64"))
    end

    test "handles invalid input image" do
      result = MultiModal.generate_variations("invalid_data", provider: :openai)
      assert {:error, message} = result
      assert message =~ "Invalid image data"
    end
  end

  describe "audio_generation" do
    test "generates speech from text" do
      result = MultiModal.generate_speech("Hello world", provider: :openai)
      assert {:ok, audio} = result
      assert is_binary(audio.data)
      assert audio.format == "mp3"
      assert audio.mime_type == "audio/mpeg"
    end

    test "supports different voices" do
      result = MultiModal.generate_speech("Hi there", provider: :openai, voice: "alloy")
      assert {:ok, audio} = result
      assert audio.voice == "alloy"
    end

    test "supports different audio formats" do
      result = MultiModal.generate_speech("Testing", provider: :openai, format: "wav")
      assert {:ok, audio} = result
      assert audio.format == "wav"
      assert audio.mime_type == "audio/wav"
    end

    test "handles invalid voice" do
      result = MultiModal.generate_speech("Error test", provider: :openai, voice: "invalid")
      assert {:error, message} = result
      assert message =~ "Invalid voice"
    end
  end

  describe "streaming" do
    test "streams audio generation" do
      stream = MultiModal.stream_speech("Long text to speak", provider: :openai)
      assert is_struct(stream, Stream)

      chunks = Enum.take(stream, 5)
      assert length(chunks) > 0
      assert Enum.all?(chunks, &match?({:ok, _}, &1))

      # Last chunk should be valid audio data
      {:ok, last_chunk} = List.last(chunks)
      assert is_binary(last_chunk)
    end

    test "handles streaming errors" do
      stream = MultiModal.stream_speech("", provider: :openai)
      assert [{:error, message}] = Enum.take(stream, 1)
      assert message =~ "Empty text"
    end
  end
end
