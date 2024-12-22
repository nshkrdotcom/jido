defmodule JidoTest.TestAgents do
  @moduledoc false

  defmodule BasicCommands do
    @moduledoc false
    use Jido.Command

    @impl true
    def commands do
      [
        basic_default: [
          description: "Default command for testing",
          schema: []
        ]
      ]
    end

    @impl true
    def handle_command(:basic_default, _agent, _params) do
      {:ok, [{Jido.Actions.Basic.Log, message: "Default action"}]}
    end
  end

  defmodule BasicAgent do
    @moduledoc false
    use Jido.Agent,
      name: "BasicAgent",
      commands: [BasicCommands],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100]
      ]

    @impl true
    def on_before_plan(_agent, _command, _params) do
      {:ok, {:basic_default, %{}}}
    end
  end

  defmodule SimpleAgent do
    @moduledoc false
    alias Jido.Actions.Basic.Log
    alias JidoTest.Commands.{Basic, Movement, Advanced}

    use Jido.Command

    use Jido.Agent,
      name: "SimpleBot",
      commands: [Basic, Movement, Advanced],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100]
      ]

    @impl true
    def commands do
      [
        simple: [
          description: "A simple command",
          schema: [
            value: [type: :integer, required: true]
          ]
        ],
        complex: [
          description: "A complex command",
          schema: [
            value: [type: :integer, required: true]
          ]
        ]
      ]
    end

    @impl true
    def handle_command(:simple, _agent, params) do
      {:ok,
       [
         {Log, message: "Simple command executed with value: #{params.value}"}
       ]}
    end
  end

  defmodule AdvancedAgent do
    @moduledoc false
    use Jido.Agent,
      name: "AdvancedAgent",
      description: "Test agent with hooks",
      category: "test",
      tags: ["test", "hooks"],
      vsn: "1.0.0",
      commands: [JidoTest.Commands.Basic, JidoTest.Commands.Movement],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100],
        has_reported: [type: :boolean, default: false]
      ]

    # Add hook implementations for testing
    @impl true
    def on_before_validate_state(state) do
      # Add a timestamp during validation
      {:ok, Map.put(state, :last_validated, System.system_time(:second))}
    end

    @impl true
    def on_before_plan(_agent, :special, _params) do
      # Transform special command into default with no params since default command has empty schema
      {:ok, {:default, %{}}}
    end

    # Handle default case
    @impl true
    def on_before_plan(_agent, command, params) do
      {:ok, {command, params}}
    end
  end
end
