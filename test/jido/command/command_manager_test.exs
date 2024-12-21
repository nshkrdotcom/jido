defmodule JidoTest.CommandManagerTest do
  use ExUnit.Case, async: true
  alias Jido.Command.Manager
  alias JidoTest.TestActions.{BasicAction, NoSchema}

  # Test command implementation
  defmodule TestCommand do
    use Jido.Command

    @impl true
    def commands do
      [
        test_command: [
          description: "A test command",
          schema: [
            value: [type: :integer, required: true]
          ]
        ],
        another_command: [
          description: "Another test command",
          schema: [
            value: [type: :integer, required: true]
          ]
        ]
      ]
    end

    @impl true
    def handle_command(:test_command, _agent, params) do
      {:ok, [{BasicAction, params}]}
    end

    @impl true
    def handle_command(:another_command, _agent, params) do
      {:ok, [{NoSchema, params}]}
    end
  end

  describe "new/0" do
    test "creates empty command manager" do
      manager = Manager.new()
      assert map_size(manager.modules) == 0
      assert map_size(manager.commands) == 0
      assert map_size(manager.schemas) == 0
    end
  end

  describe "setup/2" do
    test "sets up manager with default commands" do
      {:ok, manager} = Manager.setup([TestCommand])

      assert TestCommand in Manager.registered_modules(manager)
      assert Jido.Commands.Default in Manager.registered_modules(manager)

      commands = Manager.registered_commands(manager)
      assert Keyword.has_key?(commands, :test_command)
      assert Keyword.has_key?(commands, :another_command)
      # Default commands
      assert Keyword.has_key?(commands, :log)
      assert Keyword.has_key?(commands, :default)
    end

    test "sets up manager without default commands" do
      {:ok, manager} = Manager.setup([TestCommand], register_default: false)

      assert TestCommand in Manager.registered_modules(manager)
      refute Jido.Commands.Default in Manager.registered_modules(manager)

      commands = Manager.registered_commands(manager)
      refute Keyword.has_key?(commands, :log)
      refute Keyword.has_key?(commands, :default)
    end

    test "handles registration failures" do
      defmodule InvalidCommand do
        use Jido.Command

        def commands do
          [invalid: [wrong: "spec"]]
        end
      end

      assert {:error, _reason} = Manager.setup([InvalidCommand])
    end

    test "registers multiple command modules" do
      defmodule ExtraCommand do
        use Jido.Command

        def commands do
          [
            extra: [
              description: "Extra command",
              schema: [value: [type: :string, required: true]]
            ]
          ]
        end
      end

      {:ok, manager} = Manager.setup([TestCommand, ExtraCommand])

      assert TestCommand in Manager.registered_modules(manager)
      assert ExtraCommand in Manager.registered_modules(manager)
      assert Jido.Commands.Default in Manager.registered_modules(manager)

      commands = Manager.registered_commands(manager)
      assert Keyword.has_key?(commands, :test_command)
      assert Keyword.has_key?(commands, :another_command)
      assert Keyword.has_key?(commands, :extra)
    end
  end

  describe "register/2" do
    test "registers valid command module" do
      {:ok, manager} = Manager.new() |> Manager.register(TestCommand)

      assert map_size(manager.modules) == 1
      assert map_size(manager.commands) == 2
      assert map_size(manager.schemas) == 2
    end

    test "prevents duplicate module registration" do
      {:ok, manager} = Manager.new() |> Manager.register(TestCommand)

      assert {:error, "Module JidoTest.CommandManagerTest.TestCommand already registered"} =
               Manager.register(manager, TestCommand)
    end

    test "prevents duplicate command names" do
      defmodule DuplicateCommand do
        use Jido.Command

        def commands do
          [test_command: [description: "Duplicate", schema: []]]
        end
      end

      {:ok, manager} = Manager.new() |> Manager.register(TestCommand)

      assert {:error,
              "Command test_command already registered by JidoTest.CommandManagerTest.TestCommand"} =
               Manager.register(manager, DuplicateCommand)
    end

    test "validates command specifications" do
      defmodule InvalidCommand do
        use Jido.Command

        def commands do
          [invalid: [wrong: "spec"]]
        end
      end

      assert {:error,
              "Invalid command invalid: unknown options [:wrong], valid options are: [:description, :schema]"} =
               Manager.new() |> Manager.register(InvalidCommand)
    end
  end

  describe "dispatch/4" do
    setup do
      {:ok, manager} = Manager.new() |> Manager.register(TestCommand)
      {:ok, manager: manager}
    end

    test "dispatches valid command with valid params", %{manager: manager} do
      assert {:ok, [{BasicAction, [value: 123]}]} =
               Manager.dispatch(manager, :test_command, nil, %{value: 123})
    end

    test "validates command parameters", %{manager: manager} do
      assert {:error, :invalid_params,
              "Invalid parameters for Command: unknown options [:wrong], valid options are: [:value]"} =
               Manager.dispatch(manager, :test_command, nil, %{wrong: "params"})
    end

    test "returns error for unknown command", %{manager: manager} do
      assert {:error, :command_not_found, "Command :unknown not found"} =
               Manager.dispatch(manager, :unknown, nil, %{})
    end
  end

  describe "registered_commands/1" do
    test "returns list of registered commands with specs" do
      {:ok, manager} = Manager.new() |> Manager.register(TestCommand)
      commands = Manager.registered_commands(manager)

      assert length(commands) == 2
      assert Keyword.has_key?(commands, :test_command)
      assert Keyword.has_key?(commands, :another_command)
    end
  end

  describe "registered_modules/1" do
    test "returns list of registered modules" do
      {:ok, manager} = Manager.new() |> Manager.register(TestCommand)
      modules = Manager.registered_modules(manager)

      assert modules == [TestCommand]
    end
  end
end
