defmodule Jido.AI.Actions.LLMTest do
  use JidoTest.Case, async: true

  alias Jido.AI.Actions.LLM

  describe "text_generation" do
    test "generates text with default settings" do
      result = LLM.generate_text("Say hello", provider: :anthropic)
      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "generates text with custom model size" do
      result = LLM.generate_text("Say hello", provider: :anthropic, size: :large)
      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "generates text with custom parameters" do
      result =
        LLM.generate_text("Say hello",
          provider: :anthropic,
          temperature: 0.8,
          max_tokens: 100,
          stop: ["\n"]
        )

      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "validates temperature parameter" do
      result =
        LLM.generate_text("Say hello",
          provider: :anthropic,
          # Invalid
          temperature: 1.5
        )

      assert {:error, message} = result
      assert message =~ "Temperature must be"
    end

    test "validates max tokens parameter" do
      result =
        LLM.generate_text("Say hello",
          provider: :anthropic,
          # Invalid
          max_tokens: -100
        )

      assert {:error, message} = result
      assert message =~ "tokens must be positive"
    end

    test "handles unknown provider" do
      result = LLM.generate_text("Say hello", provider: :unknown_provider)
      assert {:error, message} = result
      assert message =~ "Provider not found"
    end

    test "handles missing provider" do
      result = LLM.generate_text("Say hello", [])
      assert {:error, message} = result
      assert message =~ "Provider is required"
    end

    test "handles empty prompt" do
      result = LLM.generate_text("", provider: :anthropic)
      assert {:error, message} = result
      assert message =~ "Prompt cannot be empty"
    end
  end

  describe "streaming" do
    test "streams text generation" do
      stream = LLM.stream_text("Say hello", provider: :anthropic)
      assert is_struct(stream, Stream)

      chunks = Enum.take(stream, 5)
      assert length(chunks) > 0
      assert Enum.all?(chunks, &match?({:ok, _}, &1))
      assert Enum.all?(chunks, fn {:ok, chunk} -> is_binary(chunk) end)
    end

    test "streams with custom parameters" do
      stream =
        LLM.stream_text("Say hello",
          provider: :anthropic,
          temperature: 0.8,
          max_tokens: 100
        )

      chunks = Enum.take(stream, 5)
      assert length(chunks) > 0
      assert Enum.all?(chunks, &match?({:ok, _}, &1))
    end

    test "handles streaming errors" do
      stream = LLM.stream_text("Say hello", provider: :unknown_provider)
      assert [{:error, message}] = Enum.take(stream, 1)
      assert message =~ "Provider not found"
    end
  end

  describe "chat completion" do
    test "handles chat messages" do
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Say hello"}
      ]

      result = LLM.chat(messages, provider: :anthropic)
      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "validates message format" do
      messages = [
        # Invalid role
        %{role: "invalid", content: "Invalid role"}
      ]

      result = LLM.chat(messages, provider: :anthropic)
      assert {:error, message} = result
      assert message =~ "Invalid message role"
    end

    test "handles empty messages" do
      result = LLM.chat([], provider: :anthropic)
      assert {:error, message} = result
      assert message =~ "Messages cannot be empty"
    end

    test "streams chat completion" do
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Say hello"}
      ]

      stream = LLM.stream_chat(messages, provider: :anthropic)
      assert is_struct(stream, Stream)

      chunks = Enum.take(stream, 5)
      assert length(chunks) > 0
      assert Enum.all?(chunks, &match?({:ok, _}, &1))
    end
  end
end
