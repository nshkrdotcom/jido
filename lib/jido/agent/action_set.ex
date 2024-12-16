defmodule Jido.ActionSet do
  @moduledoc """
  Encapsulates the planning state and results for an agent.

  ## Fields

  * `agent` - The agent state used for planning
  * `plan` - The generated execution plan
  * `error` - Any errors that occurred during planning
  """

  @type t :: %__MODULE__{
          agent: struct(),
          plan: list(module() | {module(), keyword()}),
          context: map(),
          result: map(),
          error: term() | nil
        }

  @derive {Inspect, only: [:agent, :plan, :context, :result, :error]}
  defstruct [:agent, :plan, :context, :result, :error]
end
