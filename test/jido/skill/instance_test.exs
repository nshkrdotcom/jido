defmodule JidoTest.Skill.InstanceTest do
  use ExUnit.Case, async: true

  alias Jido.Skill.Instance

  defmodule TestSkill do
    @moduledoc false
    use Jido.Skill,
      name: "test_skill",
      state_key: :test,
      actions: [JidoTest.SkillTestAction],
      schema: Zoi.object(%{counter: Zoi.integer() |> Zoi.default(0)})
  end

  defmodule SlackSkill do
    @moduledoc false
    use Jido.Skill,
      name: "slack",
      state_key: :slack,
      actions: [JidoTest.SkillTestAction],
      schema: Zoi.object(%{token: Zoi.string() |> Zoi.optional()})
  end

  describe "new/1" do
    test "creates instance from module alone" do
      instance = Instance.new(TestSkill)

      assert instance.module == TestSkill
      assert instance.as == nil
      assert instance.config == %{}
      assert instance.state_key == :test
      assert instance.route_prefix == "test_skill"
      assert instance.manifest.name == "test_skill"
    end

    test "creates instance from {module, map} tuple" do
      instance = Instance.new({TestSkill, %{custom: "value"}})

      assert instance.module == TestSkill
      assert instance.as == nil
      assert instance.config == %{custom: "value"}
      assert instance.state_key == :test
      assert instance.route_prefix == "test_skill"
    end

    test "creates instance from {module, keyword_list} without :as" do
      instance = Instance.new({TestSkill, [custom: "value", other: 123]})

      assert instance.module == TestSkill
      assert instance.as == nil
      assert instance.config == %{custom: "value", other: 123}
      assert instance.state_key == :test
      assert instance.route_prefix == "test_skill"
    end

    test "creates instance with :as option from keyword list" do
      instance = Instance.new({SlackSkill, as: :support, token: "support-token"})

      assert instance.module == SlackSkill
      assert instance.as == :support
      assert instance.config == %{token: "support-token"}
      assert instance.state_key == :slack_support
      assert instance.route_prefix == "support.slack"
    end

    test "creates instance with only :as option" do
      instance = Instance.new({SlackSkill, as: :sales})

      assert instance.module == SlackSkill
      assert instance.as == :sales
      assert instance.config == %{}
      assert instance.state_key == :slack_sales
      assert instance.route_prefix == "sales.slack"
    end

    test "manifest is populated from skill module" do
      instance = Instance.new(TestSkill)

      assert instance.manifest.module == TestSkill
      assert instance.manifest.name == "test_skill"
      assert instance.manifest.state_key == :test
    end
  end

  describe "derive_state_key/2" do
    test "returns base key when as is nil" do
      assert Instance.derive_state_key(:slack, nil) == :slack
      assert Instance.derive_state_key(:database, nil) == :database
    end

    test "appends alias to base key" do
      assert Instance.derive_state_key(:slack, :support) == :slack_support
      assert Instance.derive_state_key(:slack, :sales) == :slack_sales
      assert Instance.derive_state_key(:database, :primary) == :database_primary
    end
  end

  describe "derive_route_prefix/2" do
    test "returns base name when as is nil" do
      assert Instance.derive_route_prefix("slack", nil) == "slack"
      assert Instance.derive_route_prefix("database", nil) == "database"
    end

    test "prefixes with alias" do
      assert Instance.derive_route_prefix("slack", :support) == "support.slack"
      assert Instance.derive_route_prefix("slack", :sales) == "sales.slack"
      assert Instance.derive_route_prefix("database", :primary) == "primary.database"
    end
  end

  describe "multiple instances of same skill" do
    test "same skill with different :as values get different state keys" do
      support_instance = Instance.new({SlackSkill, as: :support})
      sales_instance = Instance.new({SlackSkill, as: :sales})
      default_instance = Instance.new(SlackSkill)

      assert support_instance.state_key == :slack_support
      assert sales_instance.state_key == :slack_sales
      assert default_instance.state_key == :slack

      assert support_instance.state_key != sales_instance.state_key
      assert support_instance.state_key != default_instance.state_key
      assert sales_instance.state_key != default_instance.state_key
    end

    test "same skill with different :as values get different route prefixes" do
      support_instance = Instance.new({SlackSkill, as: :support})
      sales_instance = Instance.new({SlackSkill, as: :sales})
      default_instance = Instance.new(SlackSkill)

      assert support_instance.route_prefix == "support.slack"
      assert sales_instance.route_prefix == "sales.slack"
      assert default_instance.route_prefix == "slack"
    end

    test "different configs are preserved per instance" do
      support_instance = Instance.new({SlackSkill, as: :support, token: "support-token"})
      sales_instance = Instance.new({SlackSkill, as: :sales, token: "sales-token"})

      assert support_instance.config == %{token: "support-token"}
      assert sales_instance.config == %{token: "sales-token"}
    end
  end
end
