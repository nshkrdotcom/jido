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

  alias Jido.Instruction
  alias Jido.Agent.Directive
  alias Jido.Error

  @type chain_result :: {:ok, Jido.Agent.t(), [Directive.t()]} | {:error, Error.t() | String.t()}
  @type chain_opts :: [continue_on_directive: boolean()]

  @doc """
  Executes a chain of instructions, handling directives and state transitions.

  ## Execution Flow
  1. Instructions are executed in sequence
  2. Results from each instruction feed into the next
  3. Directives are accumulated throughout the chain
  4. At the end of the chain:
     - Agent directives are applied to the agent
     - Server directives are returned with the result

  ## Parameters
    - agent: The agent struct containing pending instructions
    - opts: Optional keyword list of execution options:
      - :merge_results - boolean, merges map results into subsequent instruction params (default: true)

  ## Returns
    - `{:ok, updated_agent, server_directives}` - Chain completed successfully
      - Updated state map
      - Queue containing any directives from execution
      - List of server directives
    - `{:error, error}` - Chain execution failed
      - Contains error details

  ## Examples

      # Basic chain execution
      {:ok, updated_agent, server_directives} = Chain.run(agent)

      # Handle execution error
      {:error, error} = Chain.run(agent_with_failing_instruction)
  """
  @impl true
  @spec run(Jido.Agent.t(), chain_opts()) :: chain_result()
  def run(%{pending_instructions: instructions} = agent, opts \\ []) do
    case :queue.to_list(instructions) do
      [] ->
        # Return success result even when no instructions
        {:ok, %{agent | pending_instructions: :queue.new(), result: :ok}, []}

      instructions_list ->
        execute_chain(agent, instructions_list, opts)
    end
  end

  @spec execute_chain(Jido.Agent.t(), [Instruction.t()], keyword()) :: chain_result()
  defp execute_chain(agent, instructions_list, opts) do
    merge_results = Keyword.get(opts, :merge_results, true)
    chain_opts = Keyword.put(opts, :merge_results, merge_results)

    # Clear pending instructions since we're executing them all
    agent = %{agent | pending_instructions: :queue.new()}
    execute_chain_step(instructions_list, agent, [], chain_opts)
  end

  @spec execute_chain_step([Instruction.t()], Jido.Agent.t(), [Directive.t()], keyword()) ::
          chain_result()
  defp execute_chain_step([], agent, accumulated_directives, _opts) do
    case Directive.apply_agent_directive(agent, accumulated_directives) do
      {:ok, updated_agent, server_directives} ->
        {:ok, updated_agent, server_directives}

      {:error, reason} ->
        {:error,
         %Error{type: :validation_error, message: "Invalid directive", details: %{reason: reason}}}
    end
  end

  defp execute_chain_step([instruction | remaining], agent, accumulated_directives, opts) do
    case execute_instruction(instruction, agent.state, opts) do
      {:ok, state_map, directive} ->
        # Add directive to accumulated list
        updated_directives = accumulated_directives ++ List.wrap(directive)
        handle_state_result(state_map, remaining, agent, updated_directives, opts)

      {:ok, state_map} ->
        handle_state_result(state_map, remaining, agent, accumulated_directives, opts)

      {:error, error} ->
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
    # IMPORTANT: Params should override state values
    merged_params = Map.merge(state, params)

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

  @doc false
  @spec apply_state(Jido.Agent.t(), map(), boolean()) :: Jido.Agent.t()
  defp apply_state(agent, state_map, true) do
    %{agent | state: Map.merge(agent.state, state_map), result: state_map}
  end

  defp apply_state(agent, state_map, false) do
    %{agent | result: state_map}
  end

  @spec handle_state_result(map(), [Instruction.t()], Jido.Agent.t(), [Directive.t()], keyword()) ::
          chain_result()
  defp handle_state_result(new_state, remaining, agent, accumulated_directives, opts) do
    apply_state = Keyword.get(opts, :apply_state, true)
    updated_agent = apply_state(agent, new_state, apply_state)

    execute_chain_step(remaining, updated_agent, accumulated_directives, opts)
  end
end
