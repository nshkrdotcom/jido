defmodule JidoTest.Agent.InternalTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Internal

  describe "set_state/1" do
    test "creates SetState effect" do
      effect = Internal.set_state(%{status: :running})
      assert %Internal.SetState{attrs: %{status: :running}} = effect
    end

    test "requires a map" do
      effect = Internal.set_state(%{a: 1, b: 2})
      assert effect.attrs == %{a: 1, b: 2}
    end
  end

  describe "replace_state/1" do
    test "creates ReplaceState effect" do
      effect = Internal.replace_state(%{new: :state})
      assert %Internal.ReplaceState{state: %{new: :state}} = effect
    end

    test "stores the complete new state" do
      new_state = %{completely: "new", data: 123}
      effect = Internal.replace_state(new_state)
      assert effect.state == new_state
    end
  end

  describe "delete_keys/1" do
    test "creates DeleteKeys effect" do
      effect = Internal.delete_keys([:temp, :cache])
      assert %Internal.DeleteKeys{keys: [:temp, :cache]} = effect
    end

    test "accepts empty list" do
      effect = Internal.delete_keys([])
      assert effect.keys == []
    end

    test "accepts single key" do
      effect = Internal.delete_keys([:single])
      assert effect.keys == [:single]
    end
  end

  describe "set_path/2" do
    test "creates SetPath effect" do
      effect = Internal.set_path([:config, :timeout], 5000)
      assert %Internal.SetPath{path: [:config, :timeout], value: 5000} = effect
    end

    test "accepts single-element path" do
      effect = Internal.set_path([:key], "value")
      assert effect.path == [:key]
      assert effect.value == "value"
    end

    test "accepts deep paths" do
      effect = Internal.set_path([:a, :b, :c, :d], :deep_value)
      assert effect.path == [:a, :b, :c, :d]
    end

    test "accepts any value type" do
      effect = Internal.set_path([:data], %{nested: [1, 2, 3]})
      assert effect.value == %{nested: [1, 2, 3]}
    end
  end

  describe "delete_path/1" do
    test "creates DeletePath effect" do
      effect = Internal.delete_path([:temp, :cache])
      assert %Internal.DeletePath{path: [:temp, :cache]} = effect
    end

    test "accepts single-element path" do
      effect = Internal.delete_path([:key])
      assert effect.path == [:key]
    end

    test "accepts deep paths" do
      effect = Internal.delete_path([:a, :b, :c])
      assert effect.path == [:a, :b, :c]
    end
  end

  describe "effect structs" do
    test "SetState struct fields" do
      effect = %Internal.SetState{attrs: %{a: 1}}
      assert effect.attrs == %{a: 1}
    end

    test "ReplaceState struct fields" do
      effect = %Internal.ReplaceState{state: %{b: 2}}
      assert effect.state == %{b: 2}
    end

    test "DeleteKeys struct fields" do
      effect = %Internal.DeleteKeys{keys: [:x, :y]}
      assert effect.keys == [:x, :y]
    end

    test "SetPath struct fields" do
      effect = %Internal.SetPath{path: [:p], value: :v}
      assert effect.path == [:p]
      assert effect.value == :v
    end

    test "DeletePath struct fields" do
      effect = %Internal.DeletePath{path: [:q, :r]}
      assert effect.path == [:q, :r]
    end
  end

  describe "schema functions" do
    test "SetState.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: Internal.SetState} =
               Internal.SetState.schema()
    end

    test "ReplaceState.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: Internal.ReplaceState} =
               Internal.ReplaceState.schema()
    end

    test "DeleteKeys.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: Internal.DeleteKeys} =
               Internal.DeleteKeys.schema()
    end

    test "SetPath.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: Internal.SetPath} =
               Internal.SetPath.schema()
    end

    test "DeletePath.schema/0 returns Zoi schema" do
      assert %{__struct__: Zoi.Types.Struct, module: Internal.DeletePath} =
               Internal.DeletePath.schema()
    end
  end
end
