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

  describe "validate_commands/1" do
    defmodule ValidCommand do
      use Jido.Command

      def commands do
        [
          :blank_command,
          ommitted_schema: [
            description: "Ommitted schema command"
          ],
          only_schema: [
            schema: [
              name: [type: :string, default: "world"]
            ]
          ],
          empty_schema: [
            description: "Empty schema command",
            schema: []
          ],
          nil_schema: [
            description: "Ommitted schema command",
            schema: nil
          ],
          test_command: [
            description: "A test command",
            schema: [
              input: [type: :string, required: true]
            ]
          ]
        ]
      end
    end

    defmodule InvalidCommand do
      def commands do
        [
          test_command: [
            # Invalid description type
            description: 123,
            # Invalid schema
            schema: "not a schema"
          ]
        ]
      end
    end

    defmodule MissingCommandsCommand do
      use Jido.Command
    end

    test "accepts valid command modules" do
      assert {:ok, [ValidCommand]} = Util.validate_commands([ValidCommand])
    end

    test "rejects modules without Jido.Command behaviour" do
      assert {:error, message} = Util.validate_commands([InvalidCommand])
      assert message =~ "does not implement Jido.Command behavior"
    end

    test "rejects modules with invalid command specs" do
      assert {:error, message} = Util.validate_commands([MissingCommandsCommand])
      assert message =~ "Missing commands/0 implementation"
    end

    test "rejects non-list inputs" do
      assert {:error, "Expected list of modules"} = Util.validate_commands(nil)
      assert {:error, "Expected list of modules"} = Util.validate_commands("not a list")
      assert {:error, "Expected list of modules"} = Util.validate_commands(%{})
    end
  end
end
