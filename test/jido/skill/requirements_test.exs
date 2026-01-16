defmodule JidoTest.Skill.RequirementsTest do
  use ExUnit.Case, async: true

  alias Jido.Skill.Instance
  alias Jido.Skill.Requirements

  defmodule SkillNoRequires do
    @moduledoc false
    use Jido.Skill,
      name: "no_requires",
      state_key: :no_requires,
      actions: [JidoTest.SkillTestAction]
  end

  defmodule SkillWithConfigRequires do
    @moduledoc false
    use Jido.Skill,
      name: "config_requires",
      state_key: :config_requires,
      actions: [JidoTest.SkillTestAction],
      requires: [
        {:config, :token},
        {:config, :channel}
      ]
  end

  defmodule SkillWithAppRequires do
    @moduledoc false
    use Jido.Skill,
      name: "app_requires",
      state_key: :app_requires,
      actions: [JidoTest.SkillTestAction],
      requires: [
        {:app, :elixir}
      ]
  end

  defmodule SkillWithMissingAppRequires do
    @moduledoc false
    use Jido.Skill,
      name: "missing_app_requires",
      state_key: :missing_app_requires,
      actions: [JidoTest.SkillTestAction],
      requires: [
        {:app, :nonexistent_app_xyz}
      ]
  end

  defmodule SkillWithSkillRequires do
    @moduledoc false
    use Jido.Skill,
      name: "skill_requires",
      state_key: :skill_requires,
      actions: [JidoTest.SkillTestAction],
      requires: [
        {:skill, "no_requires"}
      ]
  end

  defmodule SkillWithMixedRequires do
    @moduledoc false
    use Jido.Skill,
      name: "mixed_requires",
      state_key: :mixed_requires,
      actions: [JidoTest.SkillTestAction],
      requires: [
        {:config, :api_key},
        {:app, :elixir},
        {:skill, "no_requires"}
      ]
  end

  describe "validate_requirements/2" do
    test "returns :valid for skill with no requirements" do
      instance = Instance.new(SkillNoRequires)
      context = %{mounted_skills: [], resolved_config: %{}}

      assert {:ok, :valid} = Requirements.validate_requirements(instance, context)
    end

    test "returns :valid when config requirements are met" do
      instance = Instance.new(SkillWithConfigRequires)

      context = %{
        mounted_skills: [],
        resolved_config: %{token: "abc", channel: "#general"}
      }

      assert {:ok, :valid} = Requirements.validate_requirements(instance, context)
    end

    test "returns error when config requirements are missing" do
      instance = Instance.new(SkillWithConfigRequires)
      context = %{mounted_skills: [], resolved_config: %{token: "abc"}}

      assert {:error, missing} = Requirements.validate_requirements(instance, context)
      assert {:config, :channel} in missing
    end

    test "returns error when config value is nil" do
      instance = Instance.new(SkillWithConfigRequires)
      context = %{mounted_skills: [], resolved_config: %{token: "abc", channel: nil}}

      assert {:error, missing} = Requirements.validate_requirements(instance, context)
      assert {:config, :channel} in missing
    end

    test "returns :valid when app requirement is met" do
      instance = Instance.new(SkillWithAppRequires)
      context = %{mounted_skills: [], resolved_config: %{}}

      assert {:ok, :valid} = Requirements.validate_requirements(instance, context)
    end

    test "returns error when app requirement is not met" do
      instance = Instance.new(SkillWithMissingAppRequires)
      context = %{mounted_skills: [], resolved_config: %{}}

      assert {:error, missing} = Requirements.validate_requirements(instance, context)
      assert {:app, :nonexistent_app_xyz} in missing
    end

    test "returns :valid when skill requirement is met" do
      no_requires_instance = Instance.new(SkillNoRequires)
      skill_requires_instance = Instance.new(SkillWithSkillRequires)

      context = %{
        mounted_skills: [no_requires_instance],
        resolved_config: %{}
      }

      assert {:ok, :valid} = Requirements.validate_requirements(skill_requires_instance, context)
    end

    test "returns error when skill requirement is not met" do
      skill_requires_instance = Instance.new(SkillWithSkillRequires)
      context = %{mounted_skills: [], resolved_config: %{}}

      assert {:error, missing} =
               Requirements.validate_requirements(skill_requires_instance, context)

      assert {:skill, "no_requires"} in missing
    end

    test "returns :valid when all mixed requirements are met" do
      no_requires_instance = Instance.new(SkillNoRequires)
      mixed_instance = Instance.new(SkillWithMixedRequires)

      context = %{
        mounted_skills: [no_requires_instance],
        resolved_config: %{api_key: "secret"}
      }

      assert {:ok, :valid} = Requirements.validate_requirements(mixed_instance, context)
    end

    test "returns all missing requirements for mixed skill" do
      mixed_instance = Instance.new(SkillWithMixedRequires)
      context = %{mounted_skills: [], resolved_config: %{}}

      assert {:error, missing} = Requirements.validate_requirements(mixed_instance, context)
      assert {:config, :api_key} in missing
      assert {:skill, "no_requires"} in missing
      refute {:app, :elixir} in missing
    end

    test "uses instance config when resolved_config not in context" do
      instance = Instance.new({SkillWithConfigRequires, %{token: "abc", channel: "#test"}})
      context = %{mounted_skills: []}

      assert {:ok, :valid} = Requirements.validate_requirements(instance, context)
    end
  end

  describe "validate_all_requirements/2" do
    test "returns :valid when all skills have requirements met" do
      no_requires_instance = Instance.new(SkillNoRequires)
      app_requires_instance = Instance.new(SkillWithAppRequires)

      instances = [no_requires_instance, app_requires_instance]
      config_map = %{}

      assert {:ok, :valid} = Requirements.validate_all_requirements(instances, config_map)
    end

    test "returns error map with all missing requirements" do
      config_requires_instance = Instance.new(SkillWithConfigRequires)
      missing_app_instance = Instance.new(SkillWithMissingAppRequires)

      instances = [config_requires_instance, missing_app_instance]
      config_map = %{}

      assert {:error, missing_by_skill} =
               Requirements.validate_all_requirements(instances, config_map)

      assert Map.has_key?(missing_by_skill, "config_requires")
      assert Map.has_key?(missing_by_skill, "missing_app_requires")

      assert {:config, :token} in missing_by_skill["config_requires"]
      assert {:config, :channel} in missing_by_skill["config_requires"]
      assert {:app, :nonexistent_app_xyz} in missing_by_skill["missing_app_requires"]
    end

    test "uses config_map for resolved config per skill" do
      config_requires_instance = Instance.new(SkillWithConfigRequires)
      instances = [config_requires_instance]

      config_map = %{
        config_requires: %{token: "abc", channel: "#test"}
      }

      assert {:ok, :valid} = Requirements.validate_all_requirements(instances, config_map)
    end

    test "skill requirements check against all mounted skills" do
      no_requires_instance = Instance.new(SkillNoRequires)
      skill_requires_instance = Instance.new(SkillWithSkillRequires)

      instances = [no_requires_instance, skill_requires_instance]
      config_map = %{}

      assert {:ok, :valid} = Requirements.validate_all_requirements(instances, config_map)
    end
  end

  describe "format_error/1" do
    test "formats single skill with single requirement" do
      missing = %{"slack" => [{:config, :token}]}
      error = Requirements.format_error(missing)

      assert error =~ "Missing requirements for skills:"
      assert error =~ "slack requires {:config, :token}"
    end

    test "formats single skill with multiple requirements" do
      missing = %{"slack" => [{:config, :token}, {:app, :req}]}
      error = Requirements.format_error(missing)

      assert error =~ "slack requires {:config, :token}, {:app, :req}"
    end

    test "formats multiple skills" do
      missing = %{
        "slack" => [{:config, :token}],
        "database" => [{:app, :ecto}]
      }

      error = Requirements.format_error(missing)

      assert error =~ "Missing requirements for skills:"
      assert error =~ "slack requires"
      assert error =~ "database requires"
    end
  end
end
