defmodule Jido.Runner.Simple do
  @moduledoc """
  A simple runner that executes a single instruction from an Agent's instruction queue.

  ## Overview

  The Simple Runner follows a sequential execution model:
  1. Dequeues a single instruction from the agent's pending queue
  2. Executes the instruction via its action module
  3. Processes the result (either a state update, directive or both)
  4. Applies state changes if configured
  5. Returns the updated agent with the execution results and server directives

  ## Features
  * Single instruction execution
  * Support for directives and state results
  * Atomic execution guarantees
  * Comprehensive error handling
  * Debug logging at key execution points
  * Optional state application

  ## Error Handling
  * Invalid instructions are rejected
  * Action execution failures return error results
  * Queue empty condition handled gracefully
  * All errors preserve the original agent state
  """
  @behaviour Jido.Runner

  use ExDbug, enabled: true, truncate: false

  alias Jido.Instruction
  alias Jido.Error
  alias Jido.Agent.Directive

  alias Jido.Agent.Directive.{
    Enqueue,
    RegisterAction,
    DeregisterAction,
    Spawn,
    Kill
  }

  @type run_opts :: [apply_state: boolean()]
  @type run_result :: {:ok, Jido.Agent.t(), list()} | {:error, Error.t()}

  @doc """
  Executes a single instruction from the Agent's pending instructions queue.

  ## Execution Process
  1. Dequeues the oldest instruction from the agent's queue
  2. Creates a new Result struct to track execution
  3. Executes the instruction through its action module
  4. Processes any directives from the execution
  5. Optionally applies state changes
  6. Returns the updated agent with execution results and server directives

  ## Parameters
    * `agent` - The agent struct containing:
      * `pending_instructions` - Queue of pending instructions
      * `state` - Current agent state
      * `id` - Agent identifier
    * `opts` - Optional keyword list of execution options:
      * `apply_state` - Whether to apply state changes (default: true)

  ## Returns
    * `{:ok, updated_agent, directives}` - Successful execution with:
      * Updated state map (for state results)
      * Updated pending instructions queue
      * Any server directives from the execution
    * `{:error, reason}` - Execution failed with:
      * String error for queue empty condition
      * Error struct with details for execution failures

  ## Examples

      # Successful state update
      {:ok, updated_agent, directives} = Runner.Simple.run(agent_with_state_update)

      # Execute without applying state
      {:ok, updated_agent, directives} = Runner.Simple.run(agent_with_state_update, apply_state: false)

      # Empty queue - returns agent unchanged
      {:ok, agent, []} = Runner.Simple.run(agent_with_empty_queue)

      # Execution error
      {:error, error} = Runner.Simple.run(agent_with_failing_action)

  ## Error Handling
    * Returns `{:error, "No pending instructions"}` for empty queue
    * Returns `{:error, error}` with error details for execution failures
    * All errors preserve the original agent state
    * Failed executions do not affect the remaining queue

  ## Logging
  Debug logs are emitted at key points:
    * Runner start with agent ID
    * Instruction dequeue result
    * Execution setup and workflow invocation
    * Result processing and categorization
  """
  @impl true
  @spec run(Jido.Agent.t(), run_opts()) :: run_result()
  def run(%{pending_instructions: instructions} = agent, opts \\ []) do
    apply_state = Keyword.get(opts, :apply_state, true)

    dbug("Starting simple runner execution",
      agent_id: agent.id,
      queue_size: :queue.len(instructions),
      apply_state: apply_state
    )

    case :queue.out(instructions) do
      {{:value, %Instruction{} = instruction}, remaining} ->
        dbug("Dequeued instruction for execution",
          agent_id: agent.id,
          instruction: instruction,
          remaining_count: :queue.len(remaining)
        )

        agent = %{agent | pending_instructions: remaining}
        execute_instruction(agent, instruction, apply_state)

      {:empty, _} ->
        dbug("Execution skipped - empty instruction queue")
        {:ok, agent, []}
    end
  end

  @doc false
  @spec execute_instruction(Jido.Agent.t(), Instruction.t(), boolean()) :: run_result()
  defp execute_instruction(agent, instruction, apply_state) do
    dbug("Executing workflow action",
      agent_id: agent.id,
      action: instruction.action
    )

    case Jido.Workflow.run(instruction) do
      {:ok, state_map, directives} when is_list(directives) ->
        handle_directive_result(agent, state_map, directives, apply_state)

      {:ok, state_map, directive} ->
        handle_directive_result(agent, state_map, [directive], apply_state)

      {:ok, state_map} ->
        agent_with_state = apply_state(agent, state_map, apply_state)
        {:ok, agent_with_state, []}

      {:error, reason} when is_binary(reason) ->
        handle_directive_error(reason)

      {:error, error} ->
        {:error, error}
    end
  end

  @spec handle_directive_result(Jido.Agent.t(), map(), list(), boolean()) :: run_result()
  defp handle_directive_result(agent, state_map, directives, apply_state) do
    agent_with_state = apply_state(agent, state_map, apply_state)

    case Directive.apply_agent_directive(agent_with_state, directives) do
      {:ok, updated_agent, server_directives} ->
        {:ok, updated_agent, server_directives}

      {:error, reason} ->
        {:error,
         %Error{type: :validation_error, message: "Invalid directive", details: %{reason: reason}}}
    end
  end

  @spec handle_directive_error(String.t()) :: {:error, Error.t()}
  defp handle_directive_error(reason) do
    {:error, Error.validation_error("Invalid directive", %{reason: reason})}
  end

  @doc false
  @spec apply_state(Jido.Agent.t(), map(), boolean()) :: Jido.Agent.t()
  defp apply_state(agent, state_map, true) do
    %{agent | state: Map.merge(agent.state, state_map), result: state_map}
  end

  defp apply_state(agent, state_map, false) do
    %{agent | result: state_map}
  end
end
