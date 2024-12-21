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
    field(:commands, [atom()])
    field(:command_manager, Jido.Command.Manager.t())
    field(:runner, module())
    field(:dirty_state?, boolean())
    field(:pending, :queue.queue(action()))
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
                                      commands: [
                                        type: {:custom, Jido.Util, :validate_commands, []},
                                        required: false,
                                        default: [],
                                        doc:
                                          "A list of commands that this Agent implements. Commands must implement the Jido.Command behavior."
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
        ]
      ]
      alias Jido.Agent
      alias Jido.Util
      require OK
      require Logger

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          # Set up Command Manager at compile time
          command_modules = @validated_opts[:commands] || []

          {:ok, initial_manager} = Jido.Command.Manager.setup(command_modules)
          @initial_command_manager initial_manager

          # Add command_manager to struct keys
          @struct_keys [:command_manager | Keyword.keys(@agent_runtime_schema)] ++
                         Keyword.keys(@validated_opts[:schema])
          defstruct @struct_keys

          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]
          def commands, do: @validated_opts[:commands]
          def runner, do: @validated_opts[:runner]
          def schema, do: @agent_runtime_schema ++ @validated_opts[:schema]

          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              commands: @validated_opts[:commands],
              runner: @validated_opts[:runner],
              schema: @agent_runtime_schema ++ @validated_opts[:schema]
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

            defaults =
              @validated_opts[:schema]
              |> Enum.map(fn {key, opts} -> {key, Keyword.get(opts, :default)} end)
              |> Keyword.put(:id, generated_id)
              |> Keyword.put(:dirty_state?, false)
              |> Keyword.put(:pending, :queue.new())
              |> Keyword.put(:command_manager, @initial_command_manager)

            struct(__MODULE__, defaults)
          end

          @doc """
          Registers a new command module with the agent's command manager.

          ## Parameters
            - agent: The agent struct to register the command with
            - command_module: The command module to register

          ## Returns
            - `{:ok, updated_agent}` - Command registered successfully
            - `{:error, reason}` - Registration failed
          """
          @spec register_command(Agent.t(), module()) :: {:ok, Agent.t()} | {:error, String.t()}
          def register_command(agent, command_module) do
            with {:ok, updated_manager} <-
                   Jido.Command.Manager.register(agent.command_manager, command_module) do
              %{agent | command_manager: updated_manager}
              |> OK.success()
            end
          end

          @doc """
          Returns a list of commands registered with this agent's command manager.

          ## Parameters
            - agent: The agent struct to get commands from

          ## Returns
            - List of registered command specifications
          """
          @spec registered_commands(Agent.t()) :: [{atom(), Jido.Command.command_spec()}]
          def registered_commands(agent) do
            Jido.Command.Manager.registered_commands(agent.command_manager)
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
              with {:ok, updated_agent} <- do_set(agent, attrs) do
                %{updated_agent | dirty_state?: true}
                |> OK.success()
              end
            end
          end

          @spec do_set(t(), map() | keyword()) :: {:ok, t()} | {:error, String.t()}
          defp do_set(%__MODULE__{} = agent, attrs) when is_map(attrs) or is_list(attrs) do
            merged = DeepMerge.deep_merge(Map.from_struct(agent), Map.new(attrs))
            updated_agent = struct(__MODULE__, merged)

            if Map.equal?(Map.from_struct(agent), Map.from_struct(updated_agent)) do
              OK.success(updated_agent)
            else
              validate(updated_agent)
            end
          end

          @doc """
          Validates the agent's state by running it through validation hooks and schema validation.

          ## Parameters
            - agent: The agent struct to validate

          ## Returns
            - `{:ok, validated_agent}` - Agent state is valid
            - `{:error, reason}` - Validation failed
          """
          @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
          def validate(%__MODULE__{} = agent) do
            with {:ok, state} <- on_before_validate_state(Map.from_struct(agent)),
                 {:ok, validated} <- do_validate(state),
                 {:ok, final_state} <- on_after_validate_state(validated) do
              OK.success(struct(__MODULE__, final_state))
            end
          end

          @doc false
          @spec do_validate(map()) :: {:ok, map()} | {:error, String.t()}
          defp do_validate(state) do
            schema = schema()
            schema_keys = Keyword.keys(schema)
            state_to_validate = Map.take(state, schema_keys)

            case NimbleOptions.validate(Map.to_list(state_to_validate), schema) do
              {:ok, validated} -> OK.success(Map.merge(state, Map.new(validated)))
              {:error, error} -> OK.failure(Error.format_nimble_validation_error(error, "Agent"))
            end
          end

          @doc """
          Plans a sequence of actions for the agent based on a command.

          ## Parameters
            - agent: The agent struct to plan actions for
            - command: The command to execute (defaults to :default)
            - params: Optional parameters for the command (defaults to empty map)

          ## Returns
            - `{:ok, updated_agent}` - Actions were successfully planned
            - `{:error, error}` - Planning failed
          """
          @spec plan(t(), atom(), map()) :: {:ok, t()} | {:error, Jido.Error.t()}
          def plan(%__MODULE__{} = agent, command \\ :default, params \\ %{}) do
            with {:ok, {cmd, params}} <- on_before_plan(agent, command, params),
                 {:ok, actions} <-
                   Jido.Command.Manager.dispatch(agent.command_manager, cmd, agent, params) do
              new_queue = Enum.reduce(actions, agent.pending, &:queue.in(&1, &2))
              OK.success(%{agent | pending: new_queue, dirty_state?: true})
            else
              {:error, :command_not_found, reason} ->
                Error.execution_error("Command not found: #{reason}", %{
                  command: command,
                  agent_id: agent.id
                })
                |> OK.failure()

              {:error, :invalid_params, reason} ->
                Error.validation_error("Invalid command parameters: #{reason}", %{
                  command: command,
                  agent_id: agent.id,
                  params: params
                })
                |> OK.failure()

              {:error, :execution_failed, reason} ->
                Error.execution_error("Command execution failed: #{reason}", %{
                  command: command,
                  agent_id: agent.id
                })
                |> OK.failure()
            end
          end

          @doc """
          Executes all pending actions in the agent's queue.

          ## Parameters
            - agent: The agent struct containing pending actions
            - opts: Optional keyword list of execution options
              - :apply_state - Whether to apply results to agent state (default: true)

          ## Returns
            - `{:ok, updated_agent}` - Actions executed successfully
            - `{:error, error}` - Execution failed
          """
          @spec run(t(), keyword()) :: {:ok, t()} | {:error, Jido.Error.t()}
          def run(%__MODULE__{} = agent, opts \\ []) do
            pending_actions = :queue.to_list(agent.pending || :queue.new())
            apply_state = Keyword.get(opts, :apply_state, true)
            runner = runner()

            with {:ok, validated_actions} <- on_before_run(agent, pending_actions),
                 {:ok, result} <- runner.run(agent, validated_actions, opts),
                 {:ok, final_result} <- on_after_run(agent, result) do
              base_updates = %{pending: :queue.new(), dirty_state?: false}

              case {apply_state, agent.dirty_state?} do
                {true, true} ->
                  do_set(agent, Map.from_struct(final_result))
                  |> OK.map(&struct(&1, base_updates))

                {_, _} ->
                  OK.success({struct(agent, base_updates), final_result})
              end
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
            OK.success(%{agent | pending: :queue.new()})
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

          @doc """
          Validates, plans and executes a command for the agent.

          ## Parameters
            - agent: The agent struct to act on
            - command: The command to execute (defaults to :default)
            - params: Optional parameters for the command
            - opts: Optional keyword list of execution options

          ## Returns
            - `{:ok, updated_agent}` - Command executed successfully
            - `{:error, error}` - Execution failed
          """
          @spec act(t(), atom(), map(), keyword()) :: {:ok, t()} | {:error, Jido.Error.t()}
          def act(%__MODULE__{} = agent, command \\ :default, params \\ %{}, opts \\ []) do
            apply_state = Keyword.get(opts, :apply_state, true)

            with {:ok, validated_agent} <- validate(agent),
                 {:ok, updated_agent} <-
                   if(apply_state,
                     do: set(validated_agent, params),
                     else: OK.success(validated_agent)
                   ),
                 {:ok, planned_agent} <- plan(updated_agent, command, params),
                 {:ok, final_agent} <- run(planned_agent, opts) do
              OK.success(final_agent)
            end
          end

          def on_before_validate_state(state), do: OK.success(state)
          def on_after_validate_state(state), do: OK.success(state)
          def on_before_plan(agent, command, params), do: OK.success({command, params})
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
  Called before planning commands, allows preprocessing of command parameters
  and potential command routing/transformation.
  """
  @callback on_before_plan(agent :: t(), command :: atom(), params :: map()) ::
              {:ok, {atom(), map()}} | {:error, any()}

  @doc """
  Called after command planning but before execution.
  Allows inspection/modification of planned actions.
  """
  @callback on_before_run(agent :: t(), actions :: [{module(), map()}]) ::
              {:ok, [{module(), map()}]} | {:error, any()}

  @doc """
  Called after successful command execution.
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
