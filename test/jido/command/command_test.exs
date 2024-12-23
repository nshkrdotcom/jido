defmodule JidoTest.CommandTest do
  use ExUnit.Case, async: true
  alias Jido.Command
  alias JidoTest.TestActions.{BasicAction, NoSchema}

  # Test command implementation
  defmodule TestCommand do
    use Command

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
    def handle_command(:test_command, _agent, params) when is_map(params) do
      {:ok, [{BasicAction, Keyword.new([{:value, params.value}])}]}
    end

    @impl true
    def handle_command(:another_command, _agent, params) do
      {:ok, [{NoSchema, params}]}
    end
  end

  describe "command behavior" do
    test "commands/0 returns list of command specifications" do
      commands = TestCommand.commands()
      assert is_list(commands)
      assert length(commands) == 2

      test_cmd = Keyword.get(commands, :test_command)
      assert test_cmd[:description] == "A test command"
      assert Keyword.has_key?(test_cmd, :schema)
    end

    test "handle_command/3 returns actions for valid command" do
      assert {:ok, [{BasicAction, [value: 123]}]} =
               TestCommand.handle_command(:test_command, nil, %{value: 123})
    end

    test "handle_command/3 raises UndefinedFunctionError when not implemented" do
      defmodule EmptyCommand do
        use Command
        def commands, do: []
      end

      assert_raise UndefinedFunctionError, fn ->
        EmptyCommand.handle_command(:any, nil, %{})
      end
    end
  end
end
