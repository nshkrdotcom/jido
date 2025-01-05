defmodule JidoTest.TestAgentServer do
  defmodule BasicServerAgent do
    @moduledoc "Basic agent with simple schema and actions"
    use Jido.Agent,
      name: "basic_agent",
      actions: [
        JidoTest.TestActions.BasicAction,
        JidoTest.TestActions.NoSchema,
        JidoTest.TestActions.EnqueueAction,
        JidoTest.TestActions.RegisterAction,
        JidoTest.TestActions.DeregisterAction
      ],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100]
      ]

    def start_link(opts \\ []) do
      agent = BasicServerAgent.new("test")
      Jido.Agent.Server.start_link(agent: agent, name: "test_agent_server")
    end
  end
end
