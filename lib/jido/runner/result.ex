# defmodule Jido.Runner.Result do
#   @moduledoc """
#   Represents the result of executing a sequence of workflow actions.
#   Tracks the state transitions and any errors that occurred during execution.
#   """

#   use TypedStruct

#   typedstruct do
#     @typedoc "Result of executing a workflow"
#     field(:initial_state, map(), enforce: true)
#     field(:final_state, map())
#     field(:steps, [{atom(), map()}], default: [])
#     field(:errors, [Jido.Error.t()], default: [])
#     field(:status, :pending | :running | :completed | :failed, default: :pending)
#     field(:started_at, DateTime.t())
#     field(:completed_at, DateTime.t())
#   end

#   @doc """
#   Creates a new Result struct with the given initial state.
#   """
#   @spec new(map()) :: t()
#   def new(initial_state) do
#     %__MODULE__{
#       initial_state: initial_state,
#       started_at: DateTime.utc_now()
#     }
#   end

#   @doc """
#   Records a successful step execution, updating the final state.
#   """
#   @spec record_step(t(), atom(), map()) :: t()
#   def record_step(%__MODULE__{} = result, action, state) do
#     %{result | steps: result.steps ++ [{action, state}], final_state: state, status: :running}
#   end

#   @doc """
#   Records an error that occurred during execution.
#   """
#   @spec record_error(t(), Jido.Error.t()) :: t()
#   def record_error(%__MODULE__{} = result, error) do
#     %{
#       result
#       | errors: result.errors ++ [error],
#         status: :failed,
#         completed_at: DateTime.utc_now()
#     }
#   end

#   @doc """
#   Marks the result as completed successfully.
#   """
#   @spec complete(t()) :: t()
#   def complete(%__MODULE__{} = result) do
#     %{result | status: :completed, completed_at: DateTime.utc_now()}
#   end

#   @doc """
#   Returns whether the execution completed successfully.
#   """
#   @spec successful?(t()) :: boolean()
#   def successful?(%__MODULE__{status: :completed}), do: true
#   def successful?(_), do: false

#   @doc """
#   Returns whether the execution failed.
#   """
#   @spec failed?(t()) :: boolean()
#   def failed?(%__MODULE__{status: :failed}), do: true
#   def failed?(_), do: false
# end
