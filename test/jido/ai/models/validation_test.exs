defmodule Jido.AI.Models.ValidationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Models.Validation

  describe "validate_model_settings/1" do
    test "validates valid settings" do
      settings = %{
        name: "test-model",
        stop: [],
        max_input_tokens: 1000,
        max_output_tokens: 100,
        frequency_penalty: 0.5,
        presence_penalty: 0.5,
        temperature: 0.7
      }

      assert :ok = Validation.validate_model_settings(settings)
    end

    test "validates temperature" do
      settings = %{
        name: "test-model",
        stop: [],
        max_input_tokens: 1000,
        max_output_tokens: 100,
        frequency_penalty: 0.5,
        presence_penalty: 0.5,
        # Invalid
        temperature: 1.5
      }

      assert {:error, message} = Validation.validate_model_settings(settings)
      assert message =~ "Temperature must be"
    end

    test "validates token counts" do
      settings = %{
        name: "test-model",
        stop: [],
        # Invalid
        max_input_tokens: -1000,
        max_output_tokens: 100,
        frequency_penalty: 0.5,
        presence_penalty: 0.5,
        temperature: 0.7
      }

      assert {:error, message} = Validation.validate_model_settings(settings)
      assert message =~ "tokens must be positive"
    end

    test "validates penalties" do
      settings = %{
        name: "test-model",
        stop: [],
        max_input_tokens: 1000,
        max_output_tokens: 100,
        # Invalid
        frequency_penalty: 2.5,
        presence_penalty: 0.5,
        temperature: 0.7
      }

      assert {:error, message} = Validation.validate_model_settings(settings)
      assert message =~ "Penalties must be"
    end
  end
end
