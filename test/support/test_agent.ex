defmodule JidoTest.SimpleAgent do
  @moduledoc false
  alias Jido.Actions.Basic

  use Jido.Agent,
    name: "SimpleBot",
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100]
    ]

  def plan(agent) do
    {:ok,
     %Jido.ActionSet{
       agent: agent,
       plan: [
         {Basic.Log, message: "Hello, world!"},
         {Basic.Sleep, duration: 50},
         {Basic.Log, message: "Goodbye, world!"}
       ]
     }}
  end
end

defmodule JidoTest.AdvancedAgent do
  @moduledoc false
  alias Jido.Actions.Simplebot

  use Jido.Agent,
    name: "AdvancedBot",
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100],
      has_reported: [type: :boolean, default: false]
    ]

  def plan(agent) do
    actions =
      cond do
        agent.battery_level <= 20 ->
          [{Simplebot.Move, destination: :charging_station}, Simplebot.Recharge]

        agent.location != :work_area ->
          [{Simplebot.Move, destination: :work_area}]

        !agent.has_reported ->
          [Simplebot.DoWork, Simplebot.Report]

        true ->
          [Simplebot.Idle]
      end

    {:ok,
     %Jido.ActionSet{
       agent: agent,
       plan: actions
     }}
  end
end
