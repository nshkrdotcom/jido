defmodule Jido.Runner.Chain do
  @moduledoc """
  Default runner that executes actions sequentially using Chain.chain.
  """

  @behaviour Jido.Runner

  use Jido.Util, debug_enabled: true
  require Logger
  alias Jido.Workflow.Chain

  @impl true
  def run(agent, actions, opts \\ []) do
    debug("Starting action chain execution",
      agent_id: agent.id,
      actions: inspect(actions),
      opts: opts
    )

    case Chain.chain(actions, agent.state) do
      {:ok, final_state} = result ->
        debug("Action chain completed successfully",
          agent_id: agent.id,
          initial_state: inspect(agent.state),
          final_state: inspect(final_state)
        )

        debug("Returning successful result", result: result)
        {:ok, %{state: final_state}}

      {:error, reason} = error ->
        error("Action chain failed",
          agent_id: agent.id,
          reason: inspect(reason),
          actions: inspect(actions)
        )

        debug("Returning error result", error: error)
        error
    end
  end
end
