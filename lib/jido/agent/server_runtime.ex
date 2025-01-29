defmodule Jido.Agent.Server.Runtime do
  @moduledoc false
  # Handles runtime operations for the agent server.

  use Private
  use ExDbug, enabled: true

  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.Output, as: ServerOutput

  @doc """
  Executes all pending instructions in an agent's queue until empty.

  This function uses tail call recursion to process each instruction in sequence,
  ensuring the entire queue is processed before returning. It will:

  1. Check if the agent has any pending instructions
  2. If yes, execute one instruction via the agent's cmd method
  3. Recursively process any remaining instructions
  4. Handle any errors that occur during processing

  ## Parameters
    - state: The current ServerState struct containing the agent
    - opts: Optional keyword list of execution options passed to cmd

  ## Returns
    - `{:ok, state}` - All instructions processed successfully
    - `{:error, reason}` - Processing failed with reason

  ## Example

      iex> run_agent_instructions(state)
      {:ok, %ServerState{agent: updated_agent}}

  """
  @spec run_agent_instructions(ServerState.t(), keyword()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def run_agent_instructions(%ServerState{} = state, opts \\ []) do
    dbug("Starting execution of all instructions",
      agent_id: state.agent.id,
      pending_count: :queue.len(state.agent.pending_instructions)
    )

    with {:ok, running_state} <- ensure_running_state(state) do
      do_execute_all_instructions(running_state, opts)
    end
  end

  private do
    # Recursively executes all instructions in the agent's queue
    @spec do_execute_all_instructions(ServerState.t(), keyword()) ::
            {:ok, ServerState.t()} | {:error, term()}
    defp do_execute_all_instructions(%ServerState{agent: agent} = state, opts) do
      case :queue.len(agent.pending_instructions) do
        0 ->
          dbug("No more instructions to execute", agent_id: agent.id)
          ServerState.transition(state, :idle)

        count ->
          dbug("Processing next instruction",
            agent_id: agent.id,
            remaining: count
          )

          # Execute one instruction via the agent's cmd method
          case agent.__struct__.cmd(agent, [], %{}, opts) do
            {:ok, updated_agent, directives} ->
              # Update state with new agent and continue processing
              updated_state = %{state | agent: updated_agent}
              do_execute_all_instructions(updated_state, opts)

            {:error, reason} = error ->
              dbug("Instruction execution failed",
                agent_id: agent.id,
                error: reason
              )

              ServerOutput.emit_event(state, ServerSignal.cmd_failed(), %{
                error: reason
              })

              error
          end
      end
    end

    # Ensures the server is in a running state before executing instructions
    @spec ensure_running_state(ServerState.t()) :: {:ok, ServerState.t()} | {:error, term()}
    defp ensure_running_state(%ServerState{status: :idle} = state) do
      dbug("Transitioning from idle to running state")
      ServerState.transition(state, :running)
    end

    defp ensure_running_state(%ServerState{status: :running} = state) do
      dbug("State already running")
      {:ok, state}
    end

    defp ensure_running_state(%ServerState{status: status}) do
      dbug("Cannot transition to running state", current_status: status)
      {:error, {:invalid_state, status}}
    end
  end
end
