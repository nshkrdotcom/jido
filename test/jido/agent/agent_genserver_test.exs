# defmodule Jido.Agent.GenServerTest do
#   use ExUnit.Case, async: true
#   alias Jido.Error

#   defmodule TestAgent do
#     use Jido.Agent,
#       name: "test_agent",
#       description: "Test agent for GenServer functionality",
#       schema: [
#         value: [type: :integer, required: true]
#       ]
#   end

#   describe "GenServer lifecycle" do
#     test "starts agent with default values" do
#       assert {:ok, pid} = TestAgent.start_link()
#       assert Process.alive?(pid)
#       assert :ok = GenServer.stop(pid)
#     end

#     test "starts agent with custom id" do
#       id = "custom_id"
#       assert {:ok, pid} = TestAgent.start_link(id)
#       assert Process.alive?(pid)
#       assert :ok = GenServer.stop(pid)
#     end

#     test "starts agent with initial state" do
#       initial_state = %{value: 42}
#       assert {:ok, pid} = TestAgent.start_link(nil, initial_state)
#       assert Process.alive?(pid)

#       state = :sys.get_state(pid)
#       assert state.agent.state.value == 42

#       assert :ok = GenServer.stop(pid)
#     end

#     test "starts agent with custom name" do
#       name = TestAgent.CustomName
#       assert {:ok, pid} = TestAgent.start_link(nil, %{}, name: name)
#       assert Process.alive?(pid)
#       assert Process.whereis(name) == pid
#       assert :ok = GenServer.stop(pid)
#     end

#     test "child_spec returns valid supervisor child spec" do
#       opts = [id: "test", initial_state: %{value: 1}]
#       child_spec = TestAgent.child_spec(opts)

#       assert child_spec.id == TestAgent
#       assert child_spec.start == {TestAgent, :start_link, [opts]}
#     end
#   end
# end
