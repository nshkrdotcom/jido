defmodule Jido.Runner.Chain do
  @moduledoc """
  Default runner that executes actions sequentially using Chain.chain.
  """

  @behaviour Jido.Runner

  use Jido.Util, debug_enabled: false
  require Logger
  alias Jido.Workflow.Chain
  alias Jido.Error
  require OK

  @impl true
  def run(agent, actions, opts \\ []) do
    debug("Starting action chain execution",
      agent_id: agent.id,
      actions: inspect(actions),
      opts: opts
    )

    Chain.chain(actions, agent.state)
    |> handle_chain_result(agent, actions)
    |> handle_final_result()
  end

  defp handle_chain_result({:ok, final_state}, agent, _actions) do
    debug("Action chain completed successfully",
      agent_id: agent.id,
      initial_state: inspect(agent.state),
      final_state: inspect(final_state)
    )

    OK.success(final_state)
  end

  defp handle_chain_result({:error, %Error{} = error}, agent, actions) do
    error("Action chain failed with error",
      agent_id: agent.id,
      error: inspect(error),
      actions: inspect(actions)
    )

    OK.failure(error)
  end

  defp handle_chain_result({:error, reason}, agent, actions) do
    error =
      Error.execution_error(
        "Action chain failed",
        %{
          agent_id: agent.id,
          reason: reason,
          actions: actions
        }
      )

    error("Action chain failed",
      agent_id: agent.id,
      reason: inspect(reason),
      actions: inspect(actions)
    )

    OK.failure(error)
  end

  defp handle_final_result({:ok, final_state}) do
    debug("Returning successful result", state: inspect(final_state))
    OK.success(%{state: final_state})
  end

  defp handle_final_result({:error, _error} = error) do
    debug("Returning error result", error: inspect(error))
    error
  end
end
