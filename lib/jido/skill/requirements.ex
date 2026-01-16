defmodule Jido.Skill.Requirements do
  @moduledoc """
  Validates skill requirements at agent creation time.

  Skills can declare requirements in their configuration:
  - `{:config, key}` - Ensure resolved config has this key with non-nil value
  - `{:app, app_name}` - Ensure the OTP application is available
  - `{:skill, skill_name}` - Ensure another mounted skill has this name

  ## Example

      defmodule MyApp.SlackSkill do
        use Jido.Skill,
          name: "slack",
          requires: [
            {:config, :token},
            {:config, :channel},
            {:app, :req}
          ]
      end

  If requirements are not met, agent compilation will fail with a descriptive error.
  """

  alias Jido.Skill.Instance

  @type requirement :: {:config, atom()} | {:app, atom()} | {:skill, String.t() | atom()}
  @type context :: %{
          mounted_skills: [Instance.t()],
          resolved_config: map()
        }

  @doc """
  Validates requirements for a single skill instance.

  ## Parameters

  - `instance` - The skill instance with manifest containing requirements
  - `context` - Map with `:mounted_skills` and `:resolved_config`

  ## Returns

  - `{:ok, :valid}` - All requirements are met
  - `{:error, missing_requirements}` - List of unmet requirements

  ## Examples

      iex> validate_requirements(slack_instance, context)
      {:ok, :valid}

      iex> validate_requirements(slack_instance, %{mounted_skills: [], resolved_config: %{}})
      {:error, [{:config, :token}, {:app, :req}]}
  """
  @spec validate_requirements(Instance.t(), context()) ::
          {:ok, :valid} | {:error, [requirement()]}
  def validate_requirements(%Instance{} = instance, context) do
    requirements = instance.manifest.requires || []
    resolved_config = context[:resolved_config] || instance.config
    mounted_skill_names = get_mounted_skill_names(context[:mounted_skills] || [])

    missing =
      requirements
      |> Enum.reject(fn req ->
        check_requirement(req, resolved_config, mounted_skill_names)
      end)

    if missing == [] do
      {:ok, :valid}
    else
      {:error, missing}
    end
  end

  @doc """
  Validates requirements for all skill instances.

  Returns a single error listing all missing requirements grouped by skill.

  ## Parameters

  - `instances` - List of skill instances
  - `config_map` - Map of `state_key => resolved_config` for each skill

  ## Returns

  - `{:ok, :valid}` - All requirements for all skills are met
  - `{:error, missing_by_skill}` - Map of skill name => missing requirements

  ## Examples

      iex> validate_all_requirements(instances, config_map)
      {:ok, :valid}

      iex> validate_all_requirements([slack_instance], %{})
      {:error, %{"slack" => [{:config, :token}]}}
  """
  @spec validate_all_requirements([Instance.t()], map()) ::
          {:ok, :valid} | {:error, %{String.t() => [requirement()]}}
  def validate_all_requirements(instances, config_map) do
    mounted_skill_names = get_mounted_skill_names(instances)

    missing_by_skill =
      instances
      |> Enum.reduce(%{}, fn instance, acc ->
        resolved_config = Map.get(config_map, instance.state_key, instance.config)

        case validate_requirements_internal(
               instance.manifest.requires || [],
               resolved_config,
               mounted_skill_names
             ) do
          [] ->
            acc

          missing ->
            skill_name = instance.manifest.name
            Map.put(acc, skill_name, missing)
        end
      end)

    if missing_by_skill == %{} do
      {:ok, :valid}
    else
      {:error, missing_by_skill}
    end
  end

  @doc """
  Formats missing requirements into a human-readable error message.

  ## Examples

      iex> format_error(%{"slack" => [{:config, :token}, {:app, :req}]})
      "Missing requirements for skills: slack requires {:config, :token}, {:app, :req}"
  """
  @spec format_error(%{String.t() => [requirement()]}) :: String.t()
  def format_error(missing_by_skill) do
    parts =
      missing_by_skill
      |> Enum.map(fn {skill_name, requirements} ->
        reqs_str = requirements |> Enum.map(&inspect/1) |> Enum.join(", ")
        "#{skill_name} requires #{reqs_str}"
      end)
      |> Enum.join("; ")

    "Missing requirements for skills: #{parts}"
  end

  # Internal validation that returns list of missing requirements
  defp validate_requirements_internal(requirements, resolved_config, mounted_skill_names) do
    Enum.reject(requirements, fn req ->
      check_requirement(req, resolved_config, mounted_skill_names)
    end)
  end

  defp check_requirement({:config, key}, resolved_config, _mounted_skills) do
    value = Map.get(resolved_config, key)
    value != nil
  end

  defp check_requirement({:app, app_name}, _resolved_config, _mounted_skills) do
    Application.spec(app_name) != nil
  end

  defp check_requirement({:skill, skill_name}, _resolved_config, mounted_skill_names) do
    skill_name_str = to_string(skill_name)
    skill_name_str in mounted_skill_names
  end

  defp check_requirement(_unknown, _resolved_config, _mounted_skills) do
    true
  end

  defp get_mounted_skill_names(instances) do
    Enum.map(instances, fn instance -> instance.manifest.name end)
  end
end
