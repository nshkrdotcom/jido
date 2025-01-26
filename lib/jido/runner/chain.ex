defmodule Jido.Runner.Chain do
  @moduledoc """
  A runner that executes instructions sequentially with support for result chaining
  and directive-based interruption.

  ## Chain Execution
  Instructions are executed in sequence with the output of each instruction
  becoming the input for the next instruction in the chain. This enables
  data flow between instructions while maintaining state consistency.

  ## Directive Handling
  The chain supports directive-based flow control:
  * Directives are accumulated and added to the final queue
  * State changes and directives can be mixed in the chain
  * Directives do not interrupt chain execution

  ## State Management
  * Initial state flows through the chain
  * Each instruction can modify or extend the state
  * Final state reflects accumulated changes
  * Directives are added to the final queue
  """
  @behaviour Jido.Runner

  use ExDbug, enabled: false, truncate: false

  alias Jido.Instruction
  alias Jido.Agent.Directive
  alias Jido.Error

  @type chain_result :: {:ok, Jido.Agent.t()} | {:error, Error.t() | String.t()}
  @type chain_opts :: [continue_on_directive: boolean()]

  @doc """
  Executes a chain of instructions, handling directives and state transitions.

  ## Execution Flow
  1. Instructions are executed in sequence
  2. Results from each instruction feed into the next
  3. Directives are accumulated in the final queue
  4. State changes are accumulated through the chain

  ## Parameters
    - agent: The agent struct containing pending instructions
    - opts: Optional keyword list of execution options:
      - :merge_results - boolean, merges map results into subsequent instruction params (default: true)

  ## Returns
    - `{:ok, updated_agent}` - Chain completed successfully
      - Updated state map
      - Queue containing any directives from execution
      - List of encountered directives
    - `{:error, error}` - Chain execution failed
      - Contains error details

  ## Examples

      # Basic chain execution
      {:ok, updated_agent} = Chain.run(agent)

      # Handle execution error
      {:error, error} = Chain.run(agent_with_failing_instruction)
  """
  @impl true
  @spec run(Jido.Agent.t(), chain_opts()) :: chain_result()
  def run(%{pending_instructions: instructions} = agent, opts \\ []) do
    dbug("Starting chain runner",
      agent_id: agent.id,
      opts: opts
    )

    case :queue.to_list(instructions) do
      [] ->
        dbug("No instructions found")
        # Return success result even when no instructions
        {:ok, %{agent | pending_instructions: :queue.new(), result: :ok}}

      instructions_list ->
        dbug("Found #{length(instructions_list)} instructions to execute")
        execute_chain(agent, instructions_list, opts)
    end
  end

  @spec execute_chain(Jido.Agent.t(), [Instruction.t()], keyword()) :: chain_result()
  defp execute_chain(agent, instructions_list, opts) do
    merge_results = Keyword.get(opts, :merge_results, true)
    chain_opts = Keyword.put(opts, :merge_results, merge_results)

    # Clear pending instructions since we're executing them all
    agent = %{agent | pending_instructions: :queue.new()}
    execute_chain_step(instructions_list, agent, chain_opts)
  end

  @spec execute_chain_step([Instruction.t()], Jido.Agent.t(), keyword()) :: chain_result()
  defp execute_chain_step([], agent, _opts) do
    dbug("Chain execution completed successfully")
    {:ok, agent}
  end

  defp execute_chain_step([instruction | remaining], agent, opts) do
    dbug("Executing chain step",
      instruction: instruction,
      current_state: agent.state,
      instruction_params: instruction.params,
      remaining_count: length(remaining)
    )

    case execute_instruction(instruction, agent.state, opts) do
      {:ok, state_map, directive} ->
        dbug("Instruction executed successfully with directive",
          instruction: instruction,
          directive: directive
        )

        handle_directive_result(directive, remaining, %{agent | state: state_map}, opts)

      {:ok, state_map} ->
        dbug("Instruction executed successfully with state",
          instruction: instruction,
          state: state_map
        )

        handle_state_result(state_map, remaining, agent, opts)

      {:error, error} ->
        dbug("Chain step failed",
          error: error,
          instruction: instruction,
          current_state: agent.state
        )

        {:error, error}
    end
  end

  @spec execute_instruction(Instruction.t(), map(), keyword()) ::
          {:ok, map()} | {:ok, map(), Directive.t()} | {:error, term()}
  defp execute_instruction(
         %Instruction{action: action, params: params, context: context},
         state,
         opts
       ) do
    dbug("Executing workflow",
      action: action,
      params: params,
      current_state: state
    )

    # IMPORTANT: Params should override state values
    merged_params = Map.merge(state, params)

    dbug("Executing with merged params",
      action: action,
      merged_params: merged_params,
      original_params: params
    )

    context = Map.put(context, :state, state)

    case Jido.Workflow.run(action, merged_params, context, opts) do
      {:ok, state_map, directive} ->
        # Merge state_map with existing state
        merged_state = Map.merge(state, state_map)
        {:ok, merged_state, directive}

      {:ok, state_map} ->
        # Merge state_map with existing state
        merged_state = Map.merge(state, state_map)
        {:ok, merged_state}

      {:error, %Jido.Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.execution_error("Action execution failed", %{reason: reason})}
    end
  end

  @spec handle_directive_result(Directive.t(), [Instruction.t()], Jido.Agent.t(), keyword()) ::
          chain_result()
  defp handle_directive_result(directive, remaining, agent, opts) do
    dbug("Handling directive in chain",
      directive: directive,
      remaining_instructions: length(remaining),
      directive_type: directive.__struct__
    )

    # Get new instructions from directive
    case Directive.apply_directives(agent, directive) do
      {:ok, updated_agent} ->
        # Continue chain execution with remaining instructions
        # and keep any new instructions from directive in the queue
        execute_chain_step(remaining, updated_agent, opts)

      {:error, error} ->
        {:error, error}
    end
  end

  @spec handle_state_result(map(), [Instruction.t()], Jido.Agent.t(), keyword()) ::
          chain_result()
  defp handle_state_result(new_state, remaining, agent, opts) do
    dbug("Handling state transition in chain",
      previous_state: agent.state,
      new_state: new_state,
      remaining_count: length(remaining)
    )

    apply_state = Keyword.get(opts, :apply_state, true)

    updated_agent =
      if apply_state do
        %{agent | state: Map.merge(agent.state, new_state)}
      else
        %{agent | result: new_state}
      end

    dbug("Updated chain state",
      final_state: updated_agent.state,
      result: updated_agent.result,
      remaining_instructions: length(remaining)
    )

    execute_chain_step(remaining, updated_agent, opts)
  end
end
