defmodule Jido.AI.Models.RegistryTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Models.Registry

  setup do
    # Store original env vars
    env_vars = %{
      openai_api_url: System.get_env("OPENAI_API_URL"),
      anthropic_api_url: System.get_env("ANTHROPIC_API_URL"),
      ollama_server_url: System.get_env("OLLAMA_SERVER_URL"),
      small_anthropic_model: System.get_env("SMALL_ANTHROPIC_MODEL")
    }

    # Clear env vars before each test
    for {key, _} <- env_vars do
      System.delete_env(Atom.to_string(key))
    end

    on_exit(fn ->
      # Restore original env vars
      for {key, value} <- env_vars do
        if value do
          System.put_env(Atom.to_string(key), value)
        else
          System.delete_env(Atom.to_string(key))
        end
      end
    end)

    :ok
  end

  describe "provider management" do
    test "lists all supported providers" do
      providers = Registry.list_providers()
      assert is_list(providers)

      # Core providers
      assert :openai in providers
      assert :anthropic in providers
      assert :google in providers
      assert :mistral in providers
      assert :groq in providers
      assert :grok in providers

      # Cloud providers
      assert :together in providers
      assert :llamacloud in providers
      assert :ollama in providers
      assert :deepseek in providers
      assert :eternalai in providers
      assert :claude_vertex in providers

      # Additional providers
      assert :redpill in providers
      assert :openrouter in providers
      assert :galadriel in providers
      assert :fal in providers
      assert :gaianet in providers
      assert :ali_bailian in providers
      assert :volengine in providers
      assert :nanogpt in providers
      assert :hyperbolic in providers
      assert :venice in providers
      assert :nineteen_ai in providers
      assert :akash_chat_api in providers
      assert :livepeer in providers
      assert :infera in providers
    end

    test "fetches config for known provider" do
      config = Registry.get_provider(:openai)
      assert is_map(config)
      assert Map.has_key?(config, :endpoint)
      assert Map.has_key?(config, :model)
    end

    test "returns nil for unknown provider" do
      assert Registry.get_provider(:unknown_provider) == nil
    end

    test "uses environment variables for endpoints" do
      custom_endpoint = "https://custom.openai.com/v1"
      System.put_env("OPENAI_API_URL", custom_endpoint)

      config = Registry.get_provider(:openai)
      assert config.endpoint == custom_endpoint
    end

    test "uses environment variables for model names" do
      custom_model = "claude-custom-model"
      System.put_env("SMALL_ANTHROPIC_MODEL", custom_model)

      model = Registry.get_model_settings(:anthropic, :small)
      assert model.name == custom_model
    end

    test "falls back to default values when env vars not set" do
      System.delete_env("OPENAI_API_URL")
      System.delete_env("SMALL_ANTHROPIC_MODEL")

      openai_config = Registry.get_provider(:openai)
      assert openai_config.endpoint == "https://api.openai.com/v1"

      anthropic_model = Registry.get_model_settings(:anthropic, :small)
      assert anthropic_model.name == "claude-3-haiku-20240307"
    end
  end

  describe "model configuration" do
    test "provides model settings for different sizes" do
      for provider <- Registry.list_providers() do
        # These only support image models
        if provider != :fal and provider != :livepeer do
          config = Registry.get_provider(provider)
          assert %{model: model_config} = config
          assert Map.has_key?(model_config, :small)
          assert Map.has_key?(model_config, :medium)
          assert Map.has_key?(model_config, :large)
        end
      end
    end

    test "model settings contain required parameters" do
      config = Registry.get_provider(:anthropic)
      %{model: %{small: small_model}} = config

      assert Map.has_key?(small_model, :name)
      assert Map.has_key?(small_model, :stop)
      assert Map.has_key?(small_model, :max_input_tokens)
      assert Map.has_key?(small_model, :max_output_tokens)
      assert Map.has_key?(small_model, :temperature)
    end

    test "gets model settings by size" do
      # Ensure we use default
      System.delete_env("SMALL_ANTHROPIC_MODEL")
      small_model = Registry.get_model_settings(:anthropic, :small)
      assert is_map(small_model)
      assert small_model.name == "claude-3-haiku-20240307"
    end

    test "gets embedding model settings for supported providers" do
      embedding_providers = [:openai, :together, :llamacloud, :ollama, :gaianet, :volengine]

      for provider <- embedding_providers do
        embedding = Registry.get_embedding_settings(provider)
        assert is_map(embedding), "Expected #{provider} to support embeddings"
        assert Map.has_key?(embedding, :name)
        # Some providers specify dimensions, others don't
        if Map.has_key?(embedding, :dimensions) do
          assert is_integer(embedding.dimensions)
        end
      end
    end

    test "gets image model settings for supported providers" do
      image_providers = [
        :openai,
        :fal,
        :llamacloud,
        :together,
        :ali_bailian,
        :livepeer,
        :hyperbolic,
        :venice
      ]

      for provider <- image_providers do
        image = Registry.get_image_settings(provider)
        assert is_map(image), "Expected #{provider} to support image generation"
        assert Map.has_key?(image, :name)
      end
    end
  end
end
