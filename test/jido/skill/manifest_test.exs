defmodule JidoTest.Skill.ManifestTest do
  use ExUnit.Case, async: true

  alias Jido.Skill.Manifest

  describe "Manifest struct creation" do
    test "creates manifest with required fields" do
      manifest = %Manifest{
        module: SomeSkill,
        name: "some_skill",
        state_key: :some
      }

      assert manifest.module == SomeSkill
      assert manifest.name == "some_skill"
      assert manifest.state_key == :some
    end

    test "optional fields default correctly" do
      manifest = %Manifest{
        module: SomeSkill,
        name: "some_skill",
        state_key: :some
      }

      assert manifest.description == nil
      assert manifest.category == nil
      assert manifest.vsn == nil
      assert manifest.schema == nil
      assert manifest.config_schema == nil
      assert manifest.tags == []
      assert manifest.capabilities == []
      assert manifest.requires == []
      assert manifest.actions == []
      assert manifest.routes == []
      assert manifest.schedules == []
      assert manifest.signal_patterns == []
    end

    test "creates manifest with all fields" do
      schema = Zoi.object(%{counter: Zoi.integer()})
      config_schema = Zoi.object(%{enabled: Zoi.boolean()})

      manifest = %Manifest{
        module: FullSkill,
        name: "full_skill",
        description: "A full skill",
        category: "test",
        tags: ["tag1", "tag2"],
        vsn: "1.0.0",
        capabilities: [:messaging, :notifications],
        requires: [{:config, :token}, {:app, :req}],
        state_key: :full,
        schema: schema,
        config_schema: config_schema,
        actions: [SomeAction, AnotherAction],
        routes: [{"post", SomeAction}, {"get", AnotherAction}],
        schedules: [{"*/5 * * * *", SomeAction}],
        signal_patterns: ["skill.*"]
      }

      assert manifest.module == FullSkill
      assert manifest.name == "full_skill"
      assert manifest.description == "A full skill"
      assert manifest.category == "test"
      assert manifest.tags == ["tag1", "tag2"]
      assert manifest.vsn == "1.0.0"
      assert manifest.capabilities == [:messaging, :notifications]
      assert manifest.requires == [{:config, :token}, {:app, :req}]
      assert manifest.state_key == :full
      assert manifest.schema == schema
      assert manifest.config_schema == config_schema
      assert manifest.actions == [SomeAction, AnotherAction]
      assert manifest.routes == [{"post", SomeAction}, {"get", AnotherAction}]
      assert manifest.schedules == [{"*/5 * * * *", SomeAction}]
      assert manifest.signal_patterns == ["skill.*"]
    end
  end

  describe "Manifest.schema/0" do
    test "returns the Zoi schema for the manifest" do
      schema = Manifest.schema()
      assert is_struct(schema)
    end
  end

  describe "type specs" do
    test "manifest is a struct type" do
      manifest = %Manifest{
        module: SomeSkill,
        name: "test",
        state_key: :test
      }

      assert is_struct(manifest, Manifest)
    end
  end
end
