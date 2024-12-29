defmodule JidoTest.UtilTest do
  use ExUnit.Case

  alias Jido.Util

  @invalid_name_format "Invalid name format."
  @validate_name_error "The name must start with a letter and contain only letters, numbers, and underscores."

  describe "validate_name/1" do
    test "validate_name accepts valid names" do
      assert {:ok, "valid_name"} = Util.validate_name("valid_name")
      assert {:ok, "valid_name_123"} = Util.validate_name("valid_name_123")
      assert {:ok, "VALID_NAME"} = Util.validate_name("VALID_NAME")
    end

    test "validate_name rejects invalid names" do
      assert {:error, @validate_name_error} = Util.validate_name("invalid-name")
      assert {:error, @validate_name_error} = Util.validate_name("invalid name")
      assert {:error, @validate_name_error} = Util.validate_name("123invalid")
      assert {:error, @validate_name_error} = Util.validate_name("")
    end

    test "validate_name rejects non-string inputs" do
      assert {:error, @invalid_name_format} = Util.validate_name(123)
      assert {:error, @invalid_name_format} = Util.validate_name(%{})
      assert {:error, @invalid_name_format} = Util.validate_name(nil)
    end
  end
end
