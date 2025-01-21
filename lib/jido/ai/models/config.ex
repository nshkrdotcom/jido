defmodule Jido.AI.Models.Config do
  @moduledoc """
  Configuration management for model providers.

  This module wraps an `Agent` to allow registering or updating provider configurations
  at runtime. It also provides utility functions to create custom model settings.

  ## Key Concepts

  - **Runtime Registration**: Dynamically add or update provider configurations.
  - **Validation**: Ensures that model settings align with the constraints in `Jido.AI.Models.Validation`.
  - **Integration**: Can be used in ephemeral environments (e.g., tests) to quickly
    register custom or mock providers.

  ## Examples

      iex> {:ok, _pid} = Jido.AI.Models.Config.start_link()
      iex> config = %{
      ...>   endpoint: "https://api.custom.ai/v1",
      ...>   model: %{
      ...>     small: %{
      ...>       name: "custom-small",
      ...>       stop: [],
      ...>       max_input_tokens: 1000,
      ...>       max_output_tokens: 100,
      ...>       frequency_penalty: 0.5,
      ...>       presence_penalty: 0.5,
      ...>       temperature: 0.7
      ...>     }
      ...>   }
      ...> }
      iex> :ok = Jido.AI.Models.Config.register_provider(:custom, config)
      :ok
      iex> Jido.AI.Models.Config.update_provider(:custom, %{endpoint: "https://api.custom.ai/v2"})
      :ok
      iex> {:ok, settings} = Jido.AI.Models.Config.create_model_settings("my-model")
      {:ok, %{...}}

  """

  use Agent

  alias Jido.AI.Models.{Registry, Validation}

  @doc """
  Starts the configuration agent.

  Typically called under a supervisor:

      children = [
        {Jido.AI.Models.Config, []}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Registers a new provider at runtime.

  The provider config must follow the same structure as built-in providers:
  it should contain an optional `endpoint` key, and a `model` map with
  at least one size key (e.g., `:small`, `:medium`, or `:large`).

  ## Examples

      iex> config = %{
      ...>   endpoint: "https://api.custom.ai/v1",
      ...>   model: %{ small: %{ name: "my-small-model", max_input_tokens: 1000, max_output_tokens: 256, ... } }
      ...> }
      iex> Jido.AI.Models.Config.register_provider(:my_provider, config)
      :ok
  """
  @spec register_provider(Registry.provider(), Registry.provider_config()) ::
          :ok | {:error, String.t()}
  def register_provider(name, config) when is_atom(name) do
    with :ok <- validate_provider_config(config),
         :ok <- store_provider(name, config) do
      :ok
    end
  end

  @doc """
  Updates an existing provider's configuration.

  Only the specified fields in `updates` will be changed. The rest remain
  as previously configured. If the resulting merged config is invalid,
  an error is returned.

  ## Examples

      iex> Jido.AI.Models.Config.update_provider(:my_provider, %{endpoint: "https://new-endpoint"})
      :ok
  """
  @spec update_provider(Registry.provider(), map()) :: :ok | {:error, String.t()}
  def update_provider(name, updates) when is_atom(name) and is_map(updates) do
    with {:ok, current_config} <- get_stored_provider(name),
         merged_config <- deep_merge(current_config, updates),
         :ok <- validate_provider_config(merged_config),
         :ok <- store_provider(name, merged_config) do
      :ok
    end
  end

  @doc """
  Creates a custom model configuration with validation. Useful for quickly generating
  dynamic model settings in tests or advanced user scenarios.

  ## Examples

      iex> Jido.AI.Models.Config.create_model_settings("my-new-model", max_output_tokens: 2000)
      {:ok,
       %{
         name: "my-new-model",
         max_input_tokens: 128000,
         max_output_tokens: 2000,
         ...
       }}
  """
  @spec create_model_settings(String.t(), keyword()) ::
          {:ok, Registry.model_settings()} | {:error, String.t()}
  def create_model_settings(name, opts \\ []) do
    settings = %{
      name: name,
      stop: Keyword.get(opts, :stop, []),
      max_input_tokens: Keyword.get(opts, :max_input_tokens, 128_000),
      max_output_tokens: Keyword.get(opts, :max_output_tokens, 8_192),
      frequency_penalty: Keyword.get(opts, :frequency_penalty, 0.4),
      presence_penalty: Keyword.get(opts, :presence_penalty, 0.4),
      temperature: Keyword.get(opts, :temperature, 0.7)
    }

    case Validation.validate_model_settings(settings) do
      :ok -> {:ok, settings}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

  defp validate_provider_config(%{model: model_config} = config) when is_map(model_config) do
    cond do
      not valid_endpoint?(config) ->
        {:error, "Invalid endpoint configuration"}

      not valid_model_sizes?(model_config) ->
        {:error, "Invalid model size configuration"}

      true ->
        validate_model_configs(model_config)
    end
  end

  defp validate_provider_config(_), do: {:error, "Invalid provider configuration structure"}

  defp valid_endpoint?(%{endpoint: endpoint}) when is_binary(endpoint), do: true
  defp valid_endpoint?(%{endpoint: nil}), do: true
  defp valid_endpoint?(_), do: false

  defp valid_model_sizes?(config) do
    sizes = Map.keys(config)
    valid_sizes = [:small, :medium, :large, :embedding, :image]
    Enum.all?(sizes, &(&1 in valid_sizes))
  end

  defp validate_model_configs(model_config) do
    model_config
    |> Enum.reject(fn {key, _} -> key in [:embedding, :image] end)
    |> Enum.reduce_while(:ok, fn {_size, settings}, :ok ->
      case Validation.validate_model_settings(settings) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _k, %{} = l, %{} = r -> deep_merge(l, r)
      _k, _l, r -> r
    end)
  end

  defp store_provider(name, config) do
    Agent.update(__MODULE__, &Map.put(&1, name, config))
    :ok
  end

  defp get_stored_provider(name) do
    case Agent.get(__MODULE__, &Map.get(&1, name)) do
      nil -> {:error, "Provider not found"}
      config -> {:ok, config}
    end
  end
end