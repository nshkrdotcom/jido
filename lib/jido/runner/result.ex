defmodule Jido.Runner.Result do
  @moduledoc """
  Represents the result of executing one or more instructions.
  Contains the final state and any directives for the agent.

  The Result struct tracks:
  - Initial and final state of the execution
  - Status and any errors that occurred
  - Instructions that were executed
  - Any directives generated during execution
  - Remaining pending instructions

  This is used by both the Simple and Chain runners to maintain execution state
  and return results in a consistent format.
  """
  use TypedStruct
  alias Jido.Error

  typedstruct enforce: true do
    field(:status, atom(), default: :ok)
    field(:state, map(), default: %{})
    field(:directives, list(), default: [])
    field(:error, Error.t(), default: nil)
  end
end
