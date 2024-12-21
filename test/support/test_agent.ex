defmodule JidoTest.BasicAgent do
  @moduledoc false
  use Jido.Agent,
    name: "BasicAgent",
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100]
    ]
end

defmodule JidoTest.SimpleAgent do
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

defmodule JidoTest.AdvancedAgent do
  @moduledoc false
  use Jido.Agent,
    name: "AdvancedBot",
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100],
      has_reported: [type: :boolean, default: false]
    ]

  # def plan(agent, _command \\ :default, _params \\ %{}) do
  #   actions =
  #     cond do
  #       agent.battery_level <= 20 ->
  #         [{Simplebot.Move, destination: :charging_station}, Simplebot.Recharge]

  #       agent.location != :work_area ->
  #         [{Simplebot.Move, destination: :work_area}]

  #       !agent.has_reported ->
  #         [Simplebot.DoWork, Simplebot.Report]

  #       true ->
  #         [Simplebot.Idle]
  #     end

  #   {:ok, actions}
  # end
end
