# defmodule Jido.Examples.ActionExecTest do
#   use ExUnit.Case

#   require Logger
#   alias Jido.Actions.Basic.Log, as: LogAction
#   alias JidoTest.TestAgents.BasicAgent, as: B
#   alias Jido.Signal
#   alias Jido.Instruction

#   defmodule BranchStep do
#     use Jido.Action, name: "branch"

#     def run(%{condition: condition, true_action: true_action, false_action: false_action}, context) do
#       try do
#         case !!condition do
#           true -> {:ok, %{}, true_action}
#           false -> {:ok, %{}, false_action}
#         end
#       catch
#         _kind, error ->
#           {:error, "Failed to evaluate condition: #{inspect(error)}"}
#       end
#     end
#   end

#   defmodule SequenceStep do
#     use Jido.Action, name: "sequence"

#     def run(%{steps: steps}, context) do
#       {:ok, %{}, steps}
#     end
#   end

#   defmodule Parallel do
#     use Jido.Action, name: "parallel"

#     def run(%{steps: steps}, context) do
#       # Run each step asynchronously and collect refs
#       async_refs = Enum.map(steps, fn step ->
#         Jido.Exec.run_async(step, %{}, context)
#       end)

#       # Await all results
#       results = Enum.map(async_refs, fn ref ->
#         case Jido.Exec.await(ref) do
#           {:ok, result} -> result
#           {:error, error} -> error
#         end
#       end)

#       {:ok, %{results: results}, steps}
#     end
#   end

# defmodule ExampleExec do
#   use Jido.Action,
#     name: "example_action",
#     description: "Example of an Action that wraps an entire Exec",
#     schema: [
#       input: [type: :non_neg_integer, default: 5, doc: "The number of steps to execute"]
#     ]

#   def run(%{input: steps}, context) do
#     greater_than_10? = fn x -> x > 10 end

#     action = [
#       {:step, [name: "step_1"], [{LogAction, message: "Step 1"}]},
#       {:step, [name: "step_2"], [{LogAction, message: "Step 2"}]},
#       {:step, [name: "step_3"], [{LogAction, message: "Step 3"}]},
#       {:branch, [name: "branch_1"], [
#         greater_than_10?,
#         {LogAction, message: "Greater than 10"},
#         {LogAction, message: "Less than 10"}
#       ]},
#       {:converge, [name: "converge_1"], [{LogAction, message: "Converge 1"}]},
#       {:parallel, [name: "parallel"], [
#         {:step, [name: "parallel_step_1"], [{LogAction, message: "Parallel step 1"}]},
#         {:step, [name: "parallel_step_2"], [{LogAction, message: "Parallel step 2"}]},
#         {:step, [name: "parallel_step_3"], [{LogAction, message: "Parallel step 3"}]}
#       ]}
#     ]

#     input = 5
#     output = ExecAction.run(action, context)

#     {:ok, output}
#   end
# end

# defmodule ExecAction do
#   use Jido.Action, name: "action"

#   def run(action, context) do
#     {:ok, %{}, action}
#   end

#   defp step({:step, metadata, [instruction]}) do
#     instruction = Instruction.normalize(instruction)
#     Jido.Exec.run(instruction, %{}, context)
#     {:ok, %{}, instruction}
#   end

#   defp step({:branch, metadata, [condition, true_action, false_action]}) do
#     {:ok, %{}, instruction}
#   end

#   defp step({:converge, metadata, [instruction]}) do
#     {:ok, %{}, instruction}
#   end

#   defp step({:parallel, metadata, [instructions]}) do
#     {:ok, %{}, instructions}
#   end
# end

#   test "example action" do
#     {:ok, pid} =
#       B.start_link(
#         log_level: :debug,
#         actions: [Jido.Actions.Basic.Today],
#         dispatch: [],
#         routes: [
#           {"today", %Instruction{action: Jido.Actions.Basic.Today}}
#         ]
#       )

#     # {:ok, agent_state} = B.state(pid)
#     # Logger.info("Agent state: #{inspect(agent_state, pretty: true)}")

#     result = B.call(pid, %Instruction{action: Jido.Actions.Basic.Today})
#     IO.inspect(result, pretty: true)
#   end
# end
