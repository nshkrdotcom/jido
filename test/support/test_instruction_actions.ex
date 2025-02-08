# defmodule JidoTest.TestActions.ReturnInstructionAction do
#   @moduledoc "Test action that returns an instruction as a directive"
#   def run(_params, _context) do
#     next_instruction = %Jido.Instruction{
#       action: __MODULE__,
#       params: %{value: 42},
#       context: %{}
#     }

#     {:ok, %{}, next_instruction}
#   end

#   def validate_params(_params), do: {:ok, %{}}
# end

# defmodule JidoTest.TestActions.ReturnInstructionListAction do
#   @moduledoc "Test action that returns a list of instructions as directives"
#   def run(_params, _context) do
#     instructions = [
#       %Jido.Instruction{
#         action: JidoTest.TestActions.ReturnInstructionAction,
#         params: %{value: 1},
#         context: %{}
#       },
#       %Jido.Instruction{
#         action: JidoTest.TestActions.ReturnInstructionAction,
#         params: %{value: 2},
#         context: %{}
#       }
#     ]

#     {:ok, %{}, instructions}
#   end

#   def validate_params(_params), do: {:ok, %{}}
# end
