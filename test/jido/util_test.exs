defmodule JidoTest.UtilTest do
  use ExUnit.Case

  alias Jido.Error
  alias Jido.Util

  describe "validate_name/1" do
    # test "action name is the module name" do
    #   assert FullAction.name() == "full_action"
    # end

    test "validate_name accepts valid names" do
      assert {:ok, "valid_name"} = Util.validate_name("valid_name")
      assert {:ok, "valid_name_123"} = Util.validate_name("valid_name_123")
      assert {:ok, "VALID_NAME"} = Util.validate_name("VALID_NAME")
    end

    test "validate_name rejects invalid names" do
      assert {:error, %Error{type: :validation_error}} = Util.validate_name("invalid-name")
      assert {:error, %Error{type: :validation_error}} = Util.validate_name("invalid name")
      assert {:error, %Error{type: :validation_error}} = Util.validate_name("123invalid")
      assert {:error, %Error{type: :validation_error}} = Util.validate_name("")
    end

    test "validate_name rejects non-string inputs" do
      assert {:error, %Error{type: :validation_error}} = Util.validate_name(123)
      assert {:error, %Error{type: :validation_error}} = Util.validate_name(%{})
      assert {:error, %Error{type: :validation_error}} = Util.validate_name(nil)
    end
  end
end
