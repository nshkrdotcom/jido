defmodule Jido.AI.Models.ConfigTest do
  use JidoTest.Case, async: true

  alias Jido.AI.Models.Config

  setup do
    start_supervised!(Config)
    :ok
  end

  describe "register_provider/2" do
    test "registers valid provider configuration" do
      config = %{
        endpoint: "https://api.custom.ai/v1",
        model: %{
          small: %{
            name: "custom-small",
            stop: [],
            max_input_tokens: 1000,
            max_output_tokens: 100,
            frequency_penalty: 0.5,
            presence_penalty: 0.5,
            temperature: 0.7
          }
        }
      }

      assert :ok = Config.register_provider(:custom, config)
    end

    test "rejects invalid provider configuration" do
      config = %{
        endpoint: "https://api.custom.ai/v1",
        model: %{
          small: %{
            name: "custom-small",
            # Invalid
            temperature: 1.5
          }
        }
      }

      assert {:error, message} = Config.register_provider(:custom, config)
      assert message =~ "Temperature must be"
    end

    test "rejects invalid provider structure" do
      config = %{
        endpoint: "https://api.custom.ai/v1"
        # Missing model config
      }

      assert {:error, _} = Config.register_provider(:custom, config)
    end
  end

  describe "update_provider/2" do
    test "updates existing provider configuration" do
      # First register a provider
      config = %{
        endpoint: "https://api.custom.ai/v1",
        model: %{
          small: %{
            name: "custom-small",
            stop: [],
            max_input_tokens: 1000,
            max_output_tokens: 100,
            frequency_penalty: 0.5,
            presence_penalty: 0.5,
            temperature: 0.7
          }
        }
      }

      :ok = Config.register_provider(:custom, config)

      # Then update it
      updates = %{
        endpoint: "https://api.custom.ai/v2",
        model: %{
          small: %{
            temperature: 0.8
          }
        }
      }

      assert :ok = Config.update_provider(:custom, updates)
    end

    test "rejects updates with invalid values" do
      # First register a provider
      config = %{
        endpoint: "https://api.custom.ai/v1",
        model: %{
          small: %{
            name: "custom-small",
            stop: [],
            max_input_tokens: 1000,
            max_output_tokens: 100,
            frequency_penalty: 0.5,
            presence_penalty: 0.5,
            temperature: 0.7
          }
        }
      }

      :ok = Config.register_provider(:custom, config)

      # Try invalid update
      updates = %{
        model: %{
          small: %{
            # Invalid
            temperature: 1.5
          }
        }
      }

      assert {:error, message} = Config.update_provider(:custom, updates)
      assert message =~ "Temperature must be"
    end
  end

  describe "create_model_settings/2" do
    test "creates valid model settings" do
      assert {:ok, settings} = Config.create_model_settings("test-model")
      assert settings.name == "test-model"
      # Default value
      assert settings.temperature == 0.7
    end

    test "creates model settings with custom options" do
      assert {:ok, settings} = Config.create_model_settings("test-model", temperature: 0.8)
      assert settings.temperature == 0.8
    end

    test "rejects invalid options" do
      assert {:error, message} = Config.create_model_settings("test-model", temperature: 1.5)
      assert message =~ "Temperature must be"
    end
  end
end
