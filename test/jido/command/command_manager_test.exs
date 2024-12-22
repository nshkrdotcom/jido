defmodule JidoTest.CommandManagerTest do
  use ExUnit.Case, async: true
  alias Jido.Command.Manager
  alias JidoTest.TestActions.{BasicAction, NoSchema}
  alias JidoTest.CommandTest.TestCommand

  # Test command implementation remains the same...

  describe "new/0" do
    test "creates empty command manager" do
      manager = Manager.new()
      assert map_size(manager.commands) == 0
    end
  end

  describe "setup/2" do
    test "sets up manager with default commands" do
      {:ok, manager} = Manager.setup([TestCommand])

      # Test the new command_info structure
      assert %{
               test_command: %{
                 module: TestCommand,
                 description: "A test command",
                 schema: schema1
               },
               another_command: %{
                 module: TestCommand,
                 description: "Another test command",
                 schema: schema2
               }
             } = manager.commands

      assert schema1
      assert schema2
    end

    test "handles all schema variations from Basic commands" do
      {:ok, manager} = Manager.setup([JidoTest.Commands.Basic])

      assert {:ok, _} = Manager.dispatch(manager, :blank_command, nil, %{any: "params"})
      assert {:ok, _} = Manager.dispatch(manager, :ommitted_schema, nil, %{any: "params"})
      assert {:ok, _} = Manager.dispatch(manager, :empty_schema, nil, %{any: "params"})
      assert {:ok, _} = Manager.dispatch(manager, :nil_schema, nil, %{any: "params"})

      # Test standard command with schema
      assert {:ok, _} = Manager.dispatch(manager, :greet, nil, %{name: "world"})

      assert {:error, :invalid_params, _} =
               Manager.dispatch(manager, :greet, nil, %{invalid: "param"})
    end

    test "handles empty schema command" do
      defmodule EmptySchemaCommand do
        use Jido.Command

        def commands do
          [
            no_schema: [
              description: "Command with no schema",
              schema: []
            ]
          ]
        end

        def handle_command(:no_schema, _agent, params) do
          {:ok, [{NoSchema, params}]}
        end
      end

      {:ok, manager} = Manager.setup([EmptySchemaCommand])

      assert %{
               no_schema: %{
                 module: EmptySchemaCommand,
                 description: "Command with no schema",
                 schema: nil
               }
             } = manager.commands

      # Test that any params are allowed
      assert {:ok, [{NoSchema, %{arbitrary: "value"}}]} =
               Manager.dispatch(manager, :no_schema, nil, %{arbitrary: "value"})
    end
  end

  describe "dispatch/4" do
    setup do
      {:ok, manager} = Manager.new() |> Manager.register(TestCommand)
      {:ok, manager: manager}
    end

    test "dispatches command with schema validation", %{manager: manager} do
      assert {:ok, [{BasicAction, [value: 123]}]} =
               Manager.dispatch(manager, :test_command, nil, %{value: 123})
    end

    test "allows any params for empty schema command", %{manager: manager} do
      defmodule NoSchemaCommand do
        use Jido.Command

        def commands do
          [
            free_form: [
              description: "Accept any params",
              schema: []
            ]
          ]
        end

        def handle_command(:free_form, _agent, params), do: {:ok, [{NoSchema, params}]}
      end

      {:ok, manager} = Manager.register(manager, NoSchemaCommand)

      params = %{anything: "goes", number: 42}

      assert {:ok, [{NoSchema, ^params}]} =
               Manager.dispatch(manager, :free_form, nil, params)
    end

    test "validates command parameters when schema exists", %{manager: manager} do
      assert {:error, :invalid_params, msg} =
               Manager.dispatch(manager, :test_command, nil, %{wrong: "params"})

      assert msg =~ "unknown options [:wrong]"
      assert msg =~ "valid options are: [:value]"
    end
  end

  describe "registered_commands/1" do
    test "returns command info with descriptions" do
      {:ok, manager} = Manager.new() |> Manager.register(TestCommand)
      commands = Manager.registered_commands(manager)

      assert [
               {name, %{description: desc, module: TestCommand}}
             ] = commands |> Enum.take(1)

      assert is_atom(name)
      assert is_binary(desc)
    end
  end
end
