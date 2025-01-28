defmodule Jido.Agent.Directive do
  @moduledoc """
    Provides a type-safe way to modify agent state through discrete, validated directives.

    ## Overview

    Directives are immutable instructions that can be applied to an agent to modify its state
    in predefined ways. Each directive type is implemented as a separate struct with its own
    validation rules, helping ensure type safety and consistent state transitions.

    ## Available Directives

    * `EnqueueDirective` - Adds a new instruction to the agent's pending queue
        - Requires an action atom
        - Supports optional params and context maps
        - Supports optional opts keyword list
        - Example: `%EnqueueDirective{action: :move, params: %{location: :kitchen}}`

    * `RegisterActionDirective` - Registers a new action module with the agent
        - Requires a valid module atom
        - Example: `%RegisterActionDirective{action_module: MyApp.Actions.Move}`

    * `DeregisterActionDirective` - Removes an action module from the agent
        - Requires a valid module atom
        - Example: `%DeregisterActionDirective{action_module: MyApp.Actions.Move}`

    * `SpawnDirective` - Spawns a child process under the agent's supervisor
        - Requires a module atom and arguments
        - Example: `%SpawnDirective{module: MyWorker, args: [id: 1]}`

    * `KillDirective` - Terminates a child process
        - Requires a valid PID
        - Example: `%KillDirective{pid: #PID<0.123.0>}`

    * `PublishDirective` - Broadcasts a message on a PubSub topic
        - Requires a topic string and message
        - Example: `%PublishDirective{topic: "events", message: %{type: :update}}`

    * `SubscribeDirective` - Subscribes to a PubSub topic
        - Requires a topic string
        - Example: `%SubscribeDirective{topic: "events"}`

    * `UnsubscribeDirective` - Unsubscribes from a PubSub topic
        - Requires a topic string
        - Example: `%UnsubscribeDirective{topic: "events"}`

    ## Usage

    Directives are typically created by action handlers and applied through the `apply_agent_directives/3`
    function. The function processes directives in order and ensures atomicity - if any directive
    fails, the entire operation is rolled back.

    ```elixir
    # Single directive
    directive = %EnqueueDirective{action: :move, params: %{location: :kitchen}}
    result = %Result{directives: [directive]}
    {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

    # Multiple directives
    directives = [
      %RegisterActionDirective{action_module: MyApp.Actions.Move},
      %EnqueueDirective{action: :move, params: %{location: :kitchen}}
    ]

    result = %Result{directives: directives}
    {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)
    ```

    ## Validation

    Each directive type has its own validation rules:

    * `EnqueueDirective` requires a non-nil atom for the action
    * `RegisterActionDirective` requires a valid module atom
    * `DeregisterActionDirective` requires a valid module atom
    * `SpawnDirective` requires a valid module atom and arguments
    * `KillDirective` requires a valid PID
    * `PublishDirective` requires a valid topic string and message
    * `SubscribeDirective` requires a valid topic string
    * `UnsubscribeDirective` requires a valid topic string

    Failed validation results in an error tuple being returned and processing being halted.

    ## Error Handling

    The module uses tagged tuples for error handling:

    * `{:ok, updated_agent}` - Successful application of directives
    * `{:error, reason}` - Failed validation or application

    Common error reasons include:

    * `:invalid_action` - The action specified in an `EnqueueDirective` is invalid
    * `:invalid_action_module` - The module specified in a `Register/DeregisterDirective` is invalid
    * `:invalid_module` - The module specified in a `SpawnDirective` is invalid
    * `:invalid_pid` - The PID specified in a `KillDirective` is invalid
    * `:invalid_topic` - The topic specified in a broadcast/subscribe/unsubscribe directive is invalid
  """
  use ExDbug, enabled: false
  use TypedStruct
  alias Jido.Agent
  alias Jido.Instruction

  typedstruct module: EnqueueDirective do
    @moduledoc "Directive to enqueue a new instruction"
    field(:action, atom(), enforce: true)
    field(:params, map(), default: %{})
    field(:context, map(), default: %{})
    field(:opts, keyword(), default: [])
  end

  typedstruct module: RegisterActionDirective do
    @moduledoc "Directive to register a new action module"
    field(:action_module, module(), enforce: true)
  end

  typedstruct module: DeregisterActionDirective do
    @moduledoc "Directive to deregister an existing action module"
    field(:action_module, module(), enforce: true)
  end

  typedstruct module: SpawnDirective do
    @moduledoc "Directive to spawn a child process"
    field(:module, module(), enforce: true)
    field(:args, term(), enforce: true)
  end

  typedstruct module: KillDirective do
    @moduledoc "Directive to terminate a child process"
    field(:pid, pid(), enforce: true)
  end

  @type t ::
          EnqueueDirective.t()
          | RegisterActionDirective.t()
          | DeregisterActionDirective.t()
          | SpawnDirective.t()
          | KillDirective.t()

  @type directive_result :: {:ok, Agent.t()} | {:error, term()}

  @doc """
  Checks if a value is a valid directive struct or ok-tupled directive.

  A valid directive is either:
  - A struct of type EnqueueDirective, RegisterActionDirective, or DeregisterActionDirective
  - An ok-tuple containing one of the above directive structs

  ## Parameters
    - value: Any value to check

  ## Returns
    - `true` if the value is a valid directive
    - `false` otherwise

  ## Examples

      iex> is_directive?(%EnqueueDirective{action: :test})
      true

      iex> is_directive?({:ok, %RegisterActionDirective{action_module: MyModule}})
      true

      iex> is_directive?(:not_a_directive)
      false
  """
  @spec is_directive?(term()) :: boolean()
  def is_directive?({:ok, directive}) when is_struct(directive, EnqueueDirective), do: true
  def is_directive?({:ok, directive}) when is_struct(directive, RegisterActionDirective), do: true

  def is_directive?({:ok, directive}) when is_struct(directive, DeregisterActionDirective),
    do: true

  def is_directive?({:ok, directive}) when is_struct(directive, SpawnDirective), do: true
  def is_directive?({:ok, directive}) when is_struct(directive, KillDirective), do: true

  def is_directive?(directive) when is_struct(directive, EnqueueDirective), do: true
  def is_directive?(directive) when is_struct(directive, RegisterActionDirective), do: true
  def is_directive?(directive) when is_struct(directive, DeregisterActionDirective), do: true
  def is_directive?(directive) when is_struct(directive, SpawnDirective), do: true
  def is_directive?(directive) when is_struct(directive, KillDirective), do: true
  def is_directive?(_), do: false

  @doc """
  Applies a list of directives to an agent, maintaining ordering and atomicity.
  Returns either the updated agent or an error if any directive application fails.

  ## Parameters
    - agent: The agent struct to apply directives to
    - directives: A single directive or list of directives to apply
    - opts: Optional keyword list of options (default: [])

  ## Returns
    - `{:ok, updated_agent}` - All directives were successfully applied
    - `{:error, reason}` - A directive failed to apply, with reason for failure
  """
  @spec apply_directives(Agent.t(), t() | [t()], keyword()) :: directive_result()
  def apply_directives(agent, directives, opts \\ [])

  def apply_directives(agent, directive, opts) when not is_list(directive) do
    apply_directives(agent, [directive], opts)
  end

  def apply_directives(agent, directives, opts) when is_list(directives) do
    dbug("Applying #{length(directives)} directives to agent #{agent.id}",
      agent_id: agent.id,
      directive_count: length(directives)
    )

    # Process directives in order, stopping on first error
    Enum.reduce_while(directives, {:ok, agent}, fn directive, {:ok, current_agent} ->
      case apply_directive(current_agent, directive, opts) do
        {:ok, updated_agent} -> {:cont, {:ok, updated_agent}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Applies a single directive to an agent.

  ## Parameters
    - agent: The agent struct to apply the directive to
    - directive: The directive struct to apply
    - opts: Optional keyword list of options (default: [])

  ## Returns
    - `{:ok, updated_agent}` - Directive was successfully applied
    - `{:error, reason}` - Failed to apply directive with reason
  """
  @spec apply_directive(Agent.t(), t(), keyword()) :: directive_result()
  def apply_directive(agent, %EnqueueDirective{} = directive, _opts) do
    case validate_directive(directive) do
      :ok ->
        instruction = build_instruction(directive)
        new_queue = :queue.in(instruction, agent.pending_instructions)
        dbug("Enqueued new instruction", agent_id: agent.id, action: directive.action)
        {:ok, %{agent | pending_instructions: new_queue}}

      error ->
        error
    end
  end

  def apply_directive(agent, %RegisterActionDirective{} = directive, _opts) do
    case validate_directive(directive) do
      :ok ->
        dbug("Registering action module", agent_id: agent.id, module: directive.action_module)
        Agent.register_action(agent, directive.action_module)

      error ->
        error
    end
  end

  def apply_directive(agent, %DeregisterActionDirective{} = directive, _opts) do
    case validate_directive(directive) do
      :ok ->
        dbug("Deregistering action module", agent_id: agent.id, module: directive.action_module)
        Agent.deregister_action(agent, directive.action_module)

      error ->
        error
    end
  end

  def apply_directive(agent, %SpawnDirective{} = directive, _opts) do
    case validate_directive(directive) do
      :ok ->
        dbug("Spawning child process", agent_id: agent.id, module: directive.module)
        Agent.spawn_child(agent, directive.module, directive.args)

      error ->
        error
    end
  end

  def apply_directive(agent, %KillDirective{} = directive, _opts) do
    case validate_directive(directive) do
      :ok ->
        dbug("Killing child process", agent_id: agent.id, pid: directive.pid)
        Agent.kill_child(agent, directive.pid)

      error ->
        error
    end
  end

  # Private validation functions
  @spec validate_directive(t()) :: :ok | {:error, term()}
  defp validate_directive(%EnqueueDirective{action: nil}), do: {:error, :invalid_action}
  defp validate_directive(%EnqueueDirective{action: action}) when is_atom(action), do: :ok

  defp validate_directive(%RegisterActionDirective{action_module: nil}),
    do: {:error, :invalid_action_module}

  defp validate_directive(%RegisterActionDirective{action_module: module}) when is_atom(module),
    do: :ok

  defp validate_directive(%DeregisterActionDirective{action_module: module}) when is_atom(module),
    do: :ok

  defp validate_directive(%SpawnDirective{module: nil}), do: {:error, :invalid_module}
  defp validate_directive(%SpawnDirective{module: mod}) when is_atom(mod), do: :ok

  defp validate_directive(%KillDirective{pid: pid}) when is_pid(pid), do: :ok

  defp validate_directive(%EnqueueDirective{}), do: {:error, :invalid_action}
  defp validate_directive(%RegisterActionDirective{}), do: {:error, :invalid_action_module}
  defp validate_directive(%DeregisterActionDirective{}), do: {:error, :invalid_action_module}
  defp validate_directive(%SpawnDirective{}), do: {:error, :invalid_module}
  defp validate_directive(%KillDirective{}), do: {:error, :invalid_pid}
  defp validate_directive(_), do: {:error, :invalid_directive}

  defp build_instruction(%EnqueueDirective{action: action, params: params, context: context}) do
    %Instruction{action: action, params: params, context: context}
  end

  @doc """
  Validates a single directive or list of directives.

  ## Parameters
    - directives: A single directive struct or list of directive structs to validate

  ## Returns
    - `:ok` if all directives are valid
    - `{:error, reason}` if any directive is invalid

  ## Examples

      iex> validate_directives(%EnqueueDirective{action: :test})
      :ok

      iex> validate_directives([
      ...>   %EnqueueDirective{action: :test},
      ...>   %RegisterActionDirective{action_module: MyModule}
      ...> ])
      :ok

      iex> validate_directives(%EnqueueDirective{action: nil})
      {:error, :invalid_action}
  """
  @spec validate_directives(t() | [t()]) :: :ok | {:error, term()}
  def validate_directives(directives) when is_list(directives) do
    Enum.reduce_while(directives, :ok, fn directive, :ok ->
      case validate_directive(directive) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  def validate_directives(directive), do: validate_directive(directive)
end
