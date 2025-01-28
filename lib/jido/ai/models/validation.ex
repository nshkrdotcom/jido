defmodule Jido.AI.Models.Validation do
  @moduledoc """
  Validation rules and functions for model settings.
  """

  @type validation_error :: {:error, String.t()}
  @type validation_result :: :ok | validation_error()

  @doc """
  Validates model settings according to provider-specific rules.
  """
  @spec validate_model_settings(map()) :: validation_result()
  def validate_model_settings(settings) do
    with :ok <- validate_temperature(settings),
         :ok <- validate_tokens(settings),
         :ok <- validate_penalties(settings) do
      :ok
    end
  end

  @doc """
  Validates temperature is between 0.0 and 1.0
  """
  @spec validate_temperature(map()) :: validation_result()
  def validate_temperature(%{temperature: temp})
      when is_float(temp) and temp >= 0.0 and temp <= 1.0,
      do: :ok

  def validate_temperature(%{temperature: temp}),
    do: {:error, "Temperature must be a float between 0.0 and 1.0, got: #{inspect(temp)}"}

  @doc """
  Validates token counts are positive integers
  """
  @spec validate_tokens(map()) :: validation_result()
  def validate_tokens(%{max_input_tokens: input, max_output_tokens: output})
      when is_integer(input) and input > 0 and is_integer(output) and output > 0,
      do: :ok

  def validate_tokens(settings),
    do:
      {:error,
       "Input and output tokens must be positive integers, got: #{inspect(Map.take(settings, [:max_input_tokens, :max_output_tokens]))}"}

  @doc """
  Validates frequency and presence penalties
  """
  @spec validate_penalties(map()) :: validation_result()
  def validate_penalties(%{frequency_penalty: freq, presence_penalty: pres})
      when is_float(freq) and freq >= 0.0 and freq <= 2.0 and is_float(pres) and pres >= 0.0 and
             pres <= 2.0,
      do: :ok

  def validate_penalties(settings),
    do:
      {:error,
       "Penalties must be floats between 0.0 and 2.0, got: #{inspect(Map.take(settings, [:frequency_penalty, :presence_penalty]))}"}
end
