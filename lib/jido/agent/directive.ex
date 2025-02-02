defmodule Jido.Agent.Directive do
  require Logger

  @moduledoc """
    Provides a type-safe way to modify agent state through discrete, validated directives.

    ## Overview

    Directives are immutable instructions that can be applied to an agent to modify its state
    in predefined ways. Each directive type is implemented as a separate struct with its own
    validation rules, helping ensure type safety and consistent state transitions.

    ## Available Directives

    * `Enqueue` - Adds a new instruction to the agent's pending queue
        - Requires an action atom
        - Supports optional params and context maps
        - Supports optional opts keyword list
        - Example: `%Enqueue{action: :move, params: %{location: :kitchen}}`

    * `RegisterAction` - Registers a new action module with the agent
        - Requires a valid module atom
        - Example: `%RegisterAction{action_module: MyApp.Actions.Move}`

    * `DeregisterAction` - Removes an action module from the agent
        - Requires a valid module atom
        - Example: `%DeregisterAction{action_module: MyApp.Actions.Move}`

    * `Spawn` - Spawns a child process under the agent's supervisor
        - Requires a module atom and arguments
        - Example: `%Spawn{module: MyWorker, args: [id: 1]}`

    * `Kill` - Terminates a child process
        - Requires a valid PID
        - Example: `%Kill{pid: #PID<0.123.0>}`

    ## Usage

    Directives can be applied to either an Agent or ServerState struct:

        # Apply to Agent - returns updated agent
        {:ok, updated_agent} = Directive.apply_directives(agent, directives)

        # Apply to ServerState - returns updated state
        {:ok, updated_state} = Directive.apply_directives(server_state, directives)

    Each function validates directives before applying them and returns either:
    * `{:ok, updated_state}` - Directives were successfully applied
    * `{:error, reason}` - Failed to apply directives

    ## Validation

    Each directive type has its own validation rules:

    * `Enqueue` requires a non-nil atom for the action
    * `RegisterAction` requires a valid module atom
    * `DeregisterAction` requires a valid module atom
    * `Spawn` requires a valid module atom and arguments
    * `Kill` requires a valid PID

    Failed validation results in an error tuple being returned and processing being halted.

    ## Error Handling

    The module uses tagged tuples for error handling:

    * `{:ok, updated_state}` - Successful application of directives
    * `{:error, reason}` - Failed validation or application

    Common error reasons include:

    * `:invalid_action` - The action specified in an `Enqueue` is invalid
    * `:invalid_action_module` - The module specified in a `Register/DeregisterAction` is invalid
    * `:invalid_module` - The module specified in a `Spawn` is invalid
    * `:invalid_pid` - The PID specified in a `Kill` is invalid
    * `:invalid_topic` - The topic specified in a broadcast/subscribe/unsubscribe directive is invalid

    ## Ideas
    Change Mode
    Change Verbosity
    Manage Router (add/remove/etc)
    Manage Skills (add/remove/etc)
    Manage Dispatchers (add/remove/etc)

  """
  use ExDbug, enabled: false
  @decorate_all dbug()
  use TypedStruct
  alias Jido.Agent
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Instruction

  # Define directive types
  defmodule Enqueue do
    @moduledoc "Directive to enqueue a new instruction"
    use TypedStruct

    typedstruct do
      field(:action, atom(), enforce: true)
      field(:params, map(), default: %{})
      field(:context, map(), default: %{})
      field(:opts, keyword(), default: [])
    end
  end

  defmodule RegisterAction do
    @moduledoc "Directive to register a new action module"
    use TypedStruct

    typedstruct do
      field(:action_module, module(), enforce: true)
    end
  end

  defmodule DeregisterAction do
    @moduledoc "Directive to deregister an existing action module"
    use TypedStruct

    typedstruct do
      field(:action_module, module(), enforce: true)
    end
  end

  defmodule Spawn do
    @moduledoc "Directive to spawn a child process"
    use TypedStruct

    typedstruct do
      field(:module, module(), enforce: true)
      field(:args, term(), enforce: true)
    end
  end

  defmodule Kill do
    @moduledoc "Directive to terminate a child process"
    use TypedStruct

    typedstruct do
      field(:pid, pid(), enforce: true)
    end
  end

  @type t ::
          Enqueue.t()
          | RegisterAction.t()
          | DeregisterAction.t()
          | Spawn.t()
          | Kill.t()

  @type directive_result ::
          {:ok, Agent.t(), [t()]}
          | {:ok, ServerState.t(), [t()]}
          | {:error, term()}

  # Define which directive types are agent-specific, other directives are server-specific
  @agent_directives [Enqueue, RegisterAction, DeregisterAction]

  @doc """
  Applies agent directives to an Agent struct.

  ## Parameters
    - agent: The Agent struct to modify
    - directives: A list of directives to apply
    - opts: Optional keyword list of options (default: [])

  ## Returns
    - `{:ok, updated_agent, unapplied_directives}` - Successfully applied agent directives
    - `{:error, reason}` - Failed to apply directives
  """
  @spec apply_agent_directive(Agent.t(), [t()], keyword()) :: directive_result()
  def apply_agent_directive(agent, directives, opts \\ []) do
    with :ok <- validate_directives(directives) do
      # Split and apply agent directives
      {agent_directives, server_directives} = split_directives(directives)

      Enum.reduce_while(agent_directives, {:ok, agent}, fn directive, {:ok, current_agent} ->
        Logger.info("Applying agent directive: #{directive.__struct__}")

        case apply_single_directive(current_agent, directive, opts) do
          {:ok, updated_agent} -> {:cont, {:ok, updated_agent}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, updated_agent} -> {:ok, updated_agent, server_directives}
        error -> error
      end
    end
  end

  @doc """
  Applies only server directives to a ServerState struct.

  ## Parameters
    - state: The ServerState struct to modify
    - directives: A list of directives to apply
    - opts: Optional keyword list of options (default: [])

  ## Returns
    - `{:ok, updated_state, unapplied_directives}` - Successfully applied server directives
    - `{:error, reason}` - Failed to apply directives
  """
  @spec apply_server_directive(ServerState.t(), [t()], keyword()) :: directive_result()
  def apply_server_directive(state, directives, _opts \\ []) do
    # First validate all directives
    with :ok <- validate_directives(directives) do
      {_agent_directives, server_directives} = split_directives(directives)

      {:ok, state, server_directives}
      # # First apply agent directives to the embedded agent
      # case apply_agent_directive(state.agent, agent_directives) do
      #   {:ok, updated_agent, _} ->
      #     # For now, just return the state unchanged since we can't handle server directives yet
      #     # But we still need to validate them
      #     case validate_directives(server_directives) do
      #       :ok -> {:ok, %{state | agent: updated_agent}, server_directives}
      #       error -> error
      #     end

      #   error ->
      #     error
      # end
    end
  end

  # Private helpers
  defp validate_directives(directives) do
    Enum.reduce_while(directives, :ok, fn directive, :ok ->
      case validate_directive(directive) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp apply_single_directive(agent, %Enqueue{} = directive, _opts) do
    with :ok <- validate_directive(directive) do
      instruction = %Instruction{
        action: directive.action,
        params: directive.params,
        context: directive.context,
        opts: directive.opts
      }

      {:ok, %{agent | pending_instructions: :queue.in(instruction, agent.pending_instructions)}}
    end
  end

  defp apply_single_directive(agent, %RegisterAction{action_module: module} = directive, _opts) do
    with :ok <- validate_directive(directive) do
      if module in agent.actions do
        {:ok, agent}
      else
        updated_agent = %{agent | actions: [module | agent.actions]}
        {:ok, updated_agent}
      end
    end
  end

  defp apply_single_directive(agent, %DeregisterAction{action_module: module} = directive, _opts) do
    with :ok <- validate_directive(directive) do
      updated_agent = %{agent | actions: List.delete(agent.actions, module)}
      {:ok, updated_agent}
    end
  end

  defp apply_single_directive(server_state, %Spawn{} = directive, _opts) do
    with :ok <- validate_directive(directive) do
      # For now, just return the agent unchanged since we can't spawn
      {:ok, server_state}
    end
  end

  defp apply_single_directive(server_state, %Kill{} = directive, _opts) do
    with :ok <- validate_directive(directive) do
      # For now, just return the agent unchanged since we can't kill
      {:ok, server_state}
    end
  end

  defp validate_directive(%Enqueue{action: nil}), do: {:error, :invalid_action}
  defp validate_directive(%Enqueue{action: action}) when is_atom(action), do: :ok

  defp validate_directive(%RegisterAction{action_module: nil}),
    do: {:error, :invalid_action_module}

  defp validate_directive(%RegisterAction{action_module: module}) when is_atom(module),
    do: :ok

  defp validate_directive(%DeregisterAction{action_module: module}) when is_atom(module),
    do: :ok

  defp validate_directive(%Spawn{module: nil}), do: {:error, :invalid_module}
  defp validate_directive(%Spawn{module: mod}) when is_atom(mod), do: :ok

  defp validate_directive(%Kill{pid: pid}) when is_pid(pid), do: :ok
  defp validate_directive(%Kill{}), do: {:error, :invalid_pid}

  defp validate_directive(_), do: {:error, :invalid_directive}

  def split_directives(directives) when is_list(directives) do
    Enum.split_with(directives, &is_agent_directive?/1)
  end

  def is_agent_directive?(directive) when is_struct(directive) do
    directive.__struct__ in @agent_directives
  end

  def is_agent_directive?(_), do: false
end
