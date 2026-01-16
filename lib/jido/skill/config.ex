defmodule Jido.Skill.Config do
  @moduledoc """
  Resolves and validates skill configuration.

  Config resolution merges three sources (in order of precedence):
  1. Per-agent overrides (highest priority)
  2. Application environment config (`Application.get_env(otp_app, skill_module)`)
  3. Default values from the skill's config_schema (lowest priority)

  ## Example

      # In config/config.exs:
      config :my_app, MyApp.SlackSkill,
        token: "default-token",
        channel: "#general"

      # In agent definition:
      use Jido.Agent,
        skills: [
          {MyApp.SlackSkill, %{channel: "#support"}}  # Override channel
        ]

      # Resolved config:
      %{token: "default-token", channel: "#support"}
  """

  @doc """
  Resolves configuration for a skill module by merging app env with overrides.

  ## Parameters

  - `skill_module` - The skill module (must implement `otp_app/0` and optionally `config_schema/0`)
  - `overrides` - Per-agent config overrides (map)

  ## Returns

  - `{:ok, resolved_config}` - Successfully resolved and validated config
  - `{:error, errors}` - Validation errors from Zoi schema

  ## Examples

      iex> Config.resolve_config(MyApp.SlackSkill, %{channel: "#support"})
      {:ok, %{token: "env-token", channel: "#support"}}

      iex> Config.resolve_config(MyApp.SlackSkill, %{invalid: "field"})
      {:error, [%Zoi.Error{...}]}
  """
  @spec resolve_config(module(), map()) :: {:ok, map()} | {:error, list()}
  def resolve_config(skill_module, overrides \\ %{}) do
    base_config = get_app_env_config(skill_module)
    merged_config = Map.merge(base_config, overrides)

    validate_config(skill_module, merged_config)
  end

  @doc """
  Like `resolve_config/2` but raises on validation errors.

  ## Examples

      iex> Config.resolve_config!(MyApp.SlackSkill, %{channel: "#support"})
      %{token: "env-token", channel: "#support"}

      iex> Config.resolve_config!(MyApp.SlackSkill, %{invalid: "field"})
      ** (ArgumentError) Config validation failed for MyApp.SlackSkill: ...
  """
  @spec resolve_config!(module(), map()) :: map()
  def resolve_config!(skill_module, overrides \\ %{}) do
    case resolve_config(skill_module, overrides) do
      {:ok, config} ->
        config

      {:error, errors} ->
        raise ArgumentError,
              "Config validation failed for #{inspect(skill_module)}: #{inspect(errors)}"
    end
  end

  @doc false
  @spec get_app_env_config(module()) :: map()
  def get_app_env_config(skill_module) do
    otp_app = get_otp_app(skill_module)

    if otp_app do
      Application.get_env(otp_app, skill_module, %{})
      |> normalize_to_map()
    else
      %{}
    end
  end

  defp get_otp_app(skill_module) do
    if function_exported?(skill_module, :otp_app, 0) do
      skill_module.otp_app()
    else
      nil
    end
  end

  defp normalize_to_map(config) when is_list(config), do: Map.new(config)
  defp normalize_to_map(config) when is_map(config), do: config
  defp normalize_to_map(_), do: %{}

  defp validate_config(skill_module, config) do
    config_schema = get_config_schema(skill_module)

    if config_schema do
      case Zoi.parse(config_schema, config) do
        {:ok, validated} -> {:ok, validated}
        {:error, errors} -> {:error, errors}
      end
    else
      {:ok, config}
    end
  end

  defp get_config_schema(skill_module) do
    if function_exported?(skill_module, :config_schema, 0) do
      skill_module.config_schema()
    else
      nil
    end
  end
end
