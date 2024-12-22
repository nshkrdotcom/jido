defmodule Jido.Runner.Chain do
  @moduledoc """
  Default runner that executes actions sequentially using Chain.chain.
  """

  @behaviour Jido.Runner

  require Logger
  alias Jido.Workflow.Chain

  @impl true
  def run(agent, actions, opts \\ []) do
    Logger.debug("Running action chain",
      agent_id: agent.id,
      actions: inspect(actions),
      opts: opts
    )

    case Chain.chain(actions, agent.state) do
      {:ok, final_state} ->
        Logger.debug("Action chain completed successfully",
          agent_id: agent.id,
          initial_state: inspect(agent.state),
          final_state: inspect(final_state)
        )

        {:ok, %{state: final_state}}

      {:error, reason} = error ->
        Logger.warning("Action chain failed",
          agent_id: agent.id,
          reason: inspect(reason),
          actions: inspect(actions)
        )

        error
    end
  end
end
