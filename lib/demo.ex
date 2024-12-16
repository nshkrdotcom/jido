# defmodule Demo do
#   defmodule AliceAgent do
#     use Jido.Agent,
#       planner: Jido.Planner.Simple,
#       schema: [
#         first_name: [type: :string, required: true],
#         last_name: [type: :string, required: true]
#       ]

#     # Should import the Basic actions
#     alias Jido.Actions.Basic

#     def domain do
#       [
#         Basic.Sleep,
#         {Basic.Log, [message: "Hello, world!"]},
#         {Basic.RandomSleep, [min_ms: 1000, max_ms: 5000]},
#         {Basic.Todo, [todo: "Buy groceries"]},
#         {Basic.Log, [message: "Goodbye, world!"]}
#       ]
#     end
#   end

#   def demo do
#     {:ok, pid} = AliceAgent.start_link(id: "alice", first_name: "Alice", last_name: "Doe")
#   end
# end
