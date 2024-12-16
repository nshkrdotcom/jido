defmodule Jido.ActionSet do
  @moduledoc """
  Encapsulates the planning state and results for an agent.

  An ActionSet represents the complete lifecycle of an agent's planned actions,
  including the initial state, the planned actions, execution context, results,
  and any errors that may occur during the process.

  ## Fields

  * `agent` - The agent state used for planning
  * `plan` - The generated execution plan, consisting of action modules or tuples of {module, options}
  * `context` - Additional context information for action execution
  * `result` - The results of executing the plan
  * `error` - Any errors that occurred during planning or execution
  """

  @typedoc "Represents an agent's state, typically a struct"
  @type agent :: struct()

  @typedoc "A single action in the plan, either a module or a tuple of {module, keyword options}"
  @type action :: module() | {module(), keyword()}

  @typedoc "The complete ActionSet structure"
  @type t :: %__MODULE__{
          agent: agent(),
          plan: list(action()),
          context: map(),
          result: map(),
          error: term() | nil
        }

  @derive {Inspect, only: [:agent, :plan, :context, :result, :error]}
  defstruct [:agent, :plan, :context, :result, :error]
end
