defmodule Jido.Actions.Workflow do
  alias Jido.Action

  defmodule Example do
    @moduledoc false
    use Action,
      name: "example",
      description: "Example action",
      schema: []

    def run(params, ctx) do
      sequence = [
        %Instruction{
          action: ExampleStepOne,
          params: %{}
        },
        %Instruction{
          action: ExampleStepTwo,
          params: %{}
        },
        %Instruction{
          action: ExampleStepThree,
          params: %{}
        }
      ]

      {:ok, %{}, sequence}
    end
  end

  defmodule BranchStep do
    @moduledoc false
    use Action,
      name: "branch_step",
      description: "Branches the workflow based on a condition",
      schema: [
        condition: [type: :boolean, required: true, doc: "Condition to branch on"],
        true_branch: [
          type: {:list, :module},
          required: true,
          doc: "Actions to run if condition is true"
        ],
        false_branch: [
          type: {:list, :module},
          required: true,
          doc: "Actions to run if condition is false"
        ]
      ]

    def run(%{condition: condition} = params, ctx) do
      if condition do
        {:ok, params}
      end
    end
  end
end
