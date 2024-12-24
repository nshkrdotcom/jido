defmodule Jido.Agent do
  @moduledoc """
  Defines an Agent within the Jido system.

  An Agent represents a higher-level entity that can plan and execute a series of Actions.
  Agents are defined at compile-time and provide a consistent interface for planning,
  executing, and managing complex workflows. Agents can be extended with Command plugins that
  package pre-defined sequences of Actions.

  ## Features

  - Compile-time configuration validation
  - Runtime input parameter validation
  - Consistent error handling and formatting
  - Extensible lifecycle hooks
  - JSON serialization support
  - Plugin support for pre-defined sequences of Actions
  - Dynamic planning and execution of Action sequences

  ## Usage

  To define a new Agent, use the `Jido.Agent` behavior in your module:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "Performs a complex workflow",
          category: "processing",
          tags: ["example", "demo"],
          vsn: "1.0.0",
          commands: [MyCommand1, MyCommand2]
          schema: [
            input: [type: :string, required: true]
          ]
      end

  ## Optional Overrides

  Implementing modules must define the following callback:

  - `c:plan/1`: Generates a plan (sequence of Actions) for the Agent to execute.

  """
  use TypedStruct
  alias Jido.Error
  require OK

  @type action :: module() | {module(), map()}

  typedstruct do
    field(:id, String.t())
    field(:name, String.t())
    field(:description, String.t())
    field(:category, String.t())
    field(:tags, [String.t()])
    field(:vsn, String.t())
    field(:schema, NimbleOptions.schema())
    field(:actions, [module()], default: [])
    field(:runner, module())
    field(:dirty_state?, boolean())
    field(:pending, :queue.queue(action()))
    field(:state, map(), default: %{})
    field(:result, term(), default: nil)
  end

  @agent_compiletime_options_schema NimbleOptions.new!(
                                      name: [
                                        type: {:custom, Jido.Util, :validate_name, []},
                                        required: true,
                                        doc:
                                          "The name of the Agent. Must contain only letters, numbers, and underscores."
                                      ],
                                      description: [
                                        type: :string,
                                        required: false,
                                        doc: "A description of what the Agent does."
                                      ],
                                      category: [
                                        type: :string,
                                        required: false,
                                        doc: "The category of the Agent."
                                      ],
                                      tags: [
                                        type: {:list, :string},
                                        default: [],
                                        doc: "A list of tags associated with the Agent."
                                      ],
                                      vsn: [
                                        type: :string,
                                        required: false,
                                        doc: "The version of the Agent."
                                      ],
                                      actions: [
                                        # type: {:custom, Jido.Util, :validate_actions, []},
                                        type: {:list, :atom},
                                        required: false,
                                        default: [],
                                        doc:
                                          "A list of actions that this Agent implements. Actions must implement the Jido.Action behavior."
                                      ],
                                      runner: [
                                        type: :atom,
                                        required: false,
                                        default: Jido.Runner.Chain,
                                        doc: "Module implementing the Jido.Runner behavior"
                                      ],
                                      schema: [
                                        type: :keyword_list,
                                        default: [],
                                        doc:
                                          "A NimbleOptions schema for validating the Agent's state."
                                      ]
                                    )

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@agent_compiletime_options_schema)

    quote location: :keep do
      @behaviour Jido.Agent
      @type t :: Jido.Agent.t()
      @agent_runtime_schema [
        id: [
          type: :string,
          required: true,
          doc: "The unique identifier for an instance of an Agent."
        ],
        dirty_state?: [
          type: :boolean,
          required: false,
          default: false,
          doc: "Whether the Agent state is dirty, meaning it hasn't been acted upon yet."
        ],
        pending: [
          # Reference to an erlang :queue.queue()
          type: :any,
          required: false,
          default: nil,
          doc: "A queue of pending actions for the Agent."
        ],
        actions: [
          type: {:list, :atom},
          required: false,
          default: [],
          doc:
            "A list of actions that this Agent implements. Actions must implement the Jido.Action behavior."
        ],
        state: [
          type: :any,
          doc: "The current state of the Agent."
        ],
        result: [
          type: :any,
          doc: "The result of the last action executed by the Agent."
        ]
      ]
      alias Jido.Agent
      alias Jido.Util
      require OK
      require Logger

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          @struct_keys Keyword.keys(@agent_runtime_schema)
          defstruct @struct_keys

          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]
          def actions, do: @validated_opts[:actions]
          def runner, do: @validated_opts[:runner]
          def schema, do: @validated_opts[:schema]

          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              actions: @validated_opts[:actions],
              runner: @validated_opts[:runner],
              schema: @validated_opts[:schema]
            }
          end

          def __agent_metadata__ do
            to_json()
          end

          @doc """
          Creates a new agent instance with an optional ID.
          If no ID is provided, generates a UUID.

          ## Parameters
            - id: Optional string ID for the agent. If not provided, a UUID will be generated.

          ## Returns
            - The newly created agent struct with default values initialized.
          """
          @spec new(String.t() | nil) :: t()
          def new(id \\ nil) do
            generated_id = id || Util.generate_id()

            state_defaults =
              @validated_opts[:schema]
              |> Enum.map(fn {key, opts} -> {key, Keyword.get(opts, :default)} end)

            struct(__MODULE__, %{
              id: generated_id,
              state: Map.new(state_defaults),
              dirty_state?: false,
              pending: :queue.new(),
              actions: @validated_opts[:actions] || []
            })
          end

          @doc """
          Registers a new action module with the agent.

          ## Parameters
            - agent: The agent struct to register the action with
            - action_module: The action module to register

          ## Returns
            - `{:ok, updated_agent}` - Action registered successfully
            - `{:error, reason}` - Registration failed
          """
          @spec register_action(t(), module()) :: {:ok, t()} | {:error, String.t()}
          def register_action(%__MODULE__{} = agent, action_module) do
            updated_actions = [action_module | agent.actions]
            {:ok, %{agent | actions: updated_actions}}
          end

          @doc """
          Returns a list of actions registered with this agent.

          ## Parameters
            - agent: The agent struct to get actions from

          ## Returns
            - List of registered action modules
          """
          @spec registered_actions(t()) :: [module()]
          def registered_actions(%__MODULE__{} = agent) do
            agent.actions || []
          end

          @doc """
          Updates the agent's state with the given attributes.
          Sets the dirty_state? flag if changes are made.

          ## Parameters
            - agent: The agent struct to update
            - attrs: Map or keyword list of attributes to update

          ## Returns
            - `{:ok, updated_agent}` - State updated successfully
            - `{:error, reason}` - Update failed validation
          """
          @spec set(t(), map() | keyword()) :: {:ok, t()} | {:error, String.t()}
          def set(%__MODULE__{} = agent, attrs) when is_map(attrs) or is_list(attrs) do
            if Enum.empty?(attrs) do
              OK.success(agent)
            else
              with {:ok, updated_state} <- do_set(agent.state, attrs),
                   {:ok, validated_agent} <- validate(%{agent | state: updated_state}) do
                OK.success(%{validated_agent | dirty_state?: true})
              end
            end
          end

          @spec do_set(map(), map() | keyword()) :: {:ok, map()} | {:error, String.t()}
          defp do_set(state, attrs) when is_map(attrs) or is_list(attrs) do
            merged = DeepMerge.deep_merge(state, Map.new(attrs))
            OK.success(merged)
          end

          @doc """
          Validates the agent's state by running it through validation hooks and schema validation.
          Only validates fields defined in the schema, passing through any unknown fields.

          ## Parameters
            - agent: The agent struct to validate

          ## Returns
            - `{:ok, validated_agent}` - Agent state is valid
            - `{:error, reason}` - Validation failed
          """
          @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
          def validate(%__MODULE__{} = agent) do
            with {:ok, state} <- on_before_validate_state(agent.state),
                 {:ok, validated_state} <- do_validate(agent, state),
                 {:ok, final_state} <- on_after_validate_state(validated_state) do
              OK.success(%{agent | state: final_state})
            end
          end

          @spec do_validate(t(), map()) :: {:ok, map()} | {:error, String.t()}
          defp do_validate(%__MODULE__{} = _agent, state) do
            schema = schema()

            if Enum.empty?(schema) do
              OK.success(state)
            else
              # Split state into known and unknown fields
              known_keys = Keyword.keys(schema)
              {known_state, unknown_state} = Map.split(state, known_keys)

              case NimbleOptions.validate(Enum.to_list(known_state), schema) do
                {:ok, validated} ->
                  # Merge validated known fields with unvalidated unknown fields
                  OK.success(Map.merge(unknown_state, Map.new(validated)))

                {:error, error} ->
                  Error.format_nimble_validation_error(error, "Agent")
                  |> OK.failure()
              end
            end
          end

          @doc """
          Plans one or more actions by adding them to the agent's pending queue.

          ## Parameters
            - agent: The agent struct to plan actions for
            - actions: Either:
              - A single action module
              - A tuple of {action_module, params}
              - A list of action modules
              - A list of {action_module, params} tuples
            - params: Optional parameters for single action case (defaults to empty map)

          ## Returns
            - `{:ok, updated_agent}` - Actions were successfully queued
            - `{:error, error}` - Planning failed
          """
          # def plan(%__MODULE__{} = agent, actions, params \\ %{})

          # Single action module
          def plan(%__MODULE__{} = agent, action, params) when is_atom(action) do
            do_plan_action(agent, action, params)
          end

          # Single action tuple
          def plan(%__MODULE__{} = agent, {action, action_params}, _params)
              when is_atom(action) and is_map(action_params) do
            do_plan_action(agent, action, action_params)
          end

          # List of actions or action tuples
          def plan(%__MODULE__{} = agent, actions, _params) when is_list(actions) do
            Enum.reduce_while(actions, {:ok, agent}, fn
              action, {:ok, updated_agent} when is_atom(action) ->
                case do_plan_action(updated_agent, action, %{}) do
                  {:ok, agent} -> {:cont, {:ok, agent}}
                  error -> {:halt, error}
                end

              {action, params}, {:ok, updated_agent} when is_atom(action) and is_map(params) ->
                case do_plan_action(updated_agent, action, params) do
                  {:ok, agent} -> {:cont, {:ok, agent}}
                  error -> {:halt, error}
                end

              _, {:ok, _} ->
                {:halt, {:error, "Invalid action format"}}
            end)
          end

          defp do_plan_action(%__MODULE__{} = agent, action, params) do
            if action not in registered_actions(agent) do
              Error.execution_error("Action not registered", %{
                action: action,
                agent_id: agent.id,
                params: params
              })
              |> OK.failure()
            else
              with {:ok, {action, params}} <- on_before_plan(agent, action, params) do
                new_queue = :queue.in({action, params}, agent.pending)
                OK.success(%{agent | pending: new_queue, dirty_state?: true})
              else
                {:error, reason} ->
                  Error.execution_error("Failed to plan action: #{reason}", %{
                    action: action,
                    agent_id: agent.id,
                    params: params
                  })
                  |> OK.failure()
              end
            end
          end

          @doc """
          Executes all pending actions in the agent's queue.

          ## Parameters
            - agent: The agent struct containing pending actions
            - opts: Optional keyword list of execution options
              - :apply_state - Whether to apply results to agent state (default: true)

          ## Returns
            - If apply_state is true: `{:ok, updated_agent}`
            - If apply_state is false: `{:ok, result}`
          """
          @spec run(t(), keyword()) :: {:ok, t()} | {:ok, map()} | {:error, Jido.Error.t()}
          def run(%__MODULE__{state: state} = agent, opts \\ []) do
            pending_actions = :queue.to_list(agent.pending || :queue.new())
            apply_state = Keyword.get(opts, :apply_state, true)
            runner = runner()

            with {:ok, validated_actions} <- on_before_run(agent, pending_actions),
                 {:ok, result} <- runner.run(%{agent | state: state}, validated_actions, opts),
                 {:ok, final_result} <- on_after_run(agent, result) do
              {:ok, reset_agent} = reset(agent)

              if apply_state do
                OK.success(%{reset_agent | state: final_result.state, result: final_result.state})
              else
                OK.success(%{reset_agent | result: final_result.state})
              end
            else
              {:error, %Error{type: :validation_error} = error} ->
                Error.validation_error("Invalid agent state or parameters", %{error: error})
                |> OK.failure()

              {:error, %Error{type: :planning_error} = error} ->
                Error.execution_error("Failed to plan agent actions", %{error: error})
                |> OK.failure()

              {:error, %Error{type: :execution_error} = error} ->
                Error.execution_error("Failed to execute agent actions", %{error: error})
                |> OK.failure()

              {:error, error} ->
                Error.execution_error("Agent execution failed", %{error: error})
                |> OK.failure()
            end
          end

          @doc """
          Validates, plans and executes a command for the agent.

          ## Parameters
            - agent: The agent struct to act on
            - action: The action to execute
            - params: Optional parameters for the action
            - opts: Optional keyword list of execution options
              - :apply_state - Whether to apply results to agent state (default: true)

          ## Returns
            - If apply_state is true: `{:ok, updated_agent}`
            - If apply_state is false: `{:ok, {agent, result}}`
            - On error: `{:error, error}`
          """
          @spec cmd(t(), atom(), map(), keyword()) ::
                  {:ok, t()} | {:ok, {t(), map()}} | {:error, Jido.Error.t()}
          def cmd(%__MODULE__{} = agent, action, params \\ %{}, opts \\ []) do
            with {:ok, _} <- do_validate(agent, Map.merge(agent.state, params)),
                 {:ok, planned_agent} <- plan(agent, action, params),
                 {:ok, final_agent} <- run(planned_agent, opts) do
              OK.success(final_agent)
            else
              {:error, error} ->
                OK.failure(error)
            end
          end

          @doc """
          Resets the agent's pending action queue.

          ## Parameters
            - agent: The agent struct to reset

          ## Returns
            - `{:ok, updated_agent}` - Queue was reset successfully
          """
          @spec reset(t()) :: {:ok, t()}
          def reset(%__MODULE__{} = agent) do
            OK.success(%{agent | pending: :queue.new(), dirty_state?: false, result: nil})
          end

          @doc """
          Returns the number of pending actions in the agent's queue.

          ## Parameters
            - agent: The agent struct to check

          ## Returns
            - Integer count of pending actions
          """
          @spec pending?(t()) :: non_neg_integer()
          def pending?(%__MODULE__{} = agent) do
            :queue.len(agent.pending)
          end

          def on_before_validate_state(state), do: OK.success(state)
          def on_after_validate_state(state), do: OK.success(state)
          def on_before_plan(agent, action, params), do: OK.success({action, params})
          def on_before_run(agent, actions), do: OK.success(actions)
          def on_after_run(agent, result), do: OK.success(result)
          def on_error(agent, error, context), do: OK.failure(error)

          defoverridable on_before_validate_state: 1,
                         on_after_validate_state: 1,
                         on_before_plan: 3,
                         on_before_run: 2,
                         on_after_run: 2,
                         on_error: 3

        {:error, error} ->
          Logger.warning("Invalid configuration given to use Jido.Agent: #{error}")

          error
          |> Error.format_nimble_config_error("Agent")
          |> Error.config_error()
          |> OK.failure()
      end
    end
  end

  # In Jido.Agent module:

  @doc """
  Called before validating any state changes to the Agent.
  Allows custom preprocessing of state attributes.
  """
  @callback on_before_validate_state(state :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called after state validation but before saving changes.
  Allows post-processing of validated state.
  """
  @callback on_after_validate_state(state :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called before planning actions, allows preprocessing of action parameters
  and potential action routing/transformation.
  """
  @callback on_before_plan(agent :: t(), action :: module(), params :: map()) ::
              {:ok, {module(), map()}} | {:error, any()}

  @doc """
  Called after action planning but before execution.
  Allows inspection/modification of planned actions.
  """
  @callback on_before_run(agent :: t(), actions :: [{module(), map()}]) ::
              {:ok, [{module(), map()}]} | {:error, any()}

  @doc """
  Called after successful action execution.
  Allows post-processing of execution results.
  """
  @callback on_after_run(agent :: t(), result :: map()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Called when any error occurs during the agent lifecycle.
  Provides error handling and recovery strategies.
  """
  @callback on_error(agent :: t(), error :: any(), context :: map()) ::
              {:ok, t()} | {:error, any()}

  @doc """
  Raises an error indicating that Agents cannot be defined at runtime.

  This function exists to prevent misuse of the Agent system, as Agents
  are designed to be defined at compile-time only.

  ## Returns

  Always returns `{:error, reason}` where `reason` is a config error.

  ## Examples

      iex> Jido.Agent.new()
      {:error, %Jido.Error{type: :config_error, message: "Agents should not be defined at runtime"}}

  """
  @spec new() :: {:error, Error.t()}
  @spec new(map() | keyword()) :: {:error, Error.t()}
  def new, do: new(%{})

  def new(_map_or_kwlist) do
    "Agents should not be defined at runtime"
    |> Error.config_error()
    |> OK.failure()
  end
end
