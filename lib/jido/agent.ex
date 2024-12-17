defmodule Jido.Agent do
  @moduledoc """
  Defines an Agent within the Jido system.

  An Agent represents a higher-level entity that can plan and execute a series of Actions.
  Agents are defined at compile-time and provide a consistent interface for planning,
  executing, and managing complex workflows.

  ## Features

  - Compile-time configuration validation
  - Runtime input parameter validation
  - Consistent error handling and formatting
  - Extensible lifecycle hooks
  - JSON serialization support
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
          schema: [
            input: [type: :string, required: true]
          ]

        @impl true
        def plan(agent) do
          # Your planning logic here
          {:ok, %Jido.ActionSet{agent: agent, plan: [MyAction1, MyAction2]}}
        end
      end

  ## Callbacks

  Implementing modules must define the following callback:

  - `c:plan/1`: Generates a plan (sequence of Actions) for the Agent to execute.

  """
  alias Jido.Error
  require OK

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          category: String.t(),
          tags: [String.t()],
          vsn: String.t(),
          schema: NimbleOptions.schema()
        }

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
                                      schema: [
                                        type: :keyword_list,
                                        default: [],
                                        doc:
                                          "A NimbleOptions schema for validating the Agent's input parameters."
                                      ]
                                    )
  defstruct [:name, :description, :category, :tags, :vsn, :schema]

  @callback plan(t()) :: {:ok, Jido.ActionSet.t()} | {:error, any()}

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@agent_compiletime_options_schema)

    quote location: :keep do
      @behaviour Jido.Agent
      @base_agent_schema [
        id: [
          type: :string,
          required: true,
          doc: "The unique identifier for the Agent."
        ]
      ]
      alias Jido.Agent
      alias Jido.ActionSet
      alias Jido.Workflow.Chain
      alias Jido.Util
      require OK
      require Logger

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          @struct_keys Keyword.keys(@base_agent_schema) ++ Keyword.keys(@validated_opts[:schema])
          defstruct @struct_keys

          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]
          def planner, do: @validated_opts[:planner]
          def schema, do: @validated_opts[:schema]

          def to_json do
            json = %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              planner: @validated_opts[:planner],
              schema: @validated_opts[:schema]
            }

            json
          end

          def __agent_metadata__ do
            to_json()
          end

          @doc """
          Creates a new agent instance with an optional ID.
          If no ID is provided, generates a UUID.
          """
          # @spec new(String.t() | nil) :: t()
          def new(id \\ nil) do
            generated_id = id || Util.generate_id()

            defaults =
              @validated_opts[:schema]
              |> Enum.map(fn {key, opts} -> {key, Keyword.get(opts, :default)} end)
              |> Keyword.put(:id, generated_id)

            struct(__MODULE__, defaults)
          end

          @doc """
          Updates the agent's attributes using deep merge.
          """
          def set(%__MODULE__{} = agent, attrs) when is_map(attrs) or is_list(attrs) do
            # Ensure attrs is a map for consistency
            attrs_map = Map.new(attrs)

            # Convert agent to map, deeply merge attrs, then rebuild the struct
            merged = DeepMerge.deep_merge(Map.from_struct(agent), attrs_map)
            updated_agent = struct(__MODULE__, merged)

            # Validate the updated agent
            case validate(updated_agent) do
              {:ok, valid_agent} ->
                {:ok, valid_agent}

              {:error, reason} ->
                {:error, reason}
            end
          end

          def validate(%__MODULE__{} = agent) do
            schema = @base_agent_schema ++ @validated_opts[:schema]

            # Convert the agent struct to a keyword list
            opts =
              agent
              |> Map.from_struct()
              |> Map.to_list()

            case NimbleOptions.validate(opts, schema) do
              {:ok, validated_opts} ->
                # On success, create a new struct with the validated options
                {:ok, struct(__MODULE__, validated_opts)}

              {:error, %NimbleOptions.ValidationError{} = error} ->
                # Format the validation error for clarity
                {:error, Agent.format_validation_error(error)}

              error ->
                # Unexpected error scenario
                {:error, "Unexpected error during validation: #{inspect(error)}"}
            end
          end

          def plan(%__MODULE__{} = agent) do
            raise "plan/1 must be implemented by #{__MODULE__}"
          end

          def run(%ActionSet{agent: agent, plan: plan} = _frame) do
            case Chain.chain(plan, agent) do
              {:ok, final_state} = result ->
                Logger.info("Plan executed successfully",
                  agent_id: agent.id,
                  initial_state: agent,
                  final_state: final_state
                )

                result

              {:error, reason} = error ->
                Logger.error("Plan execution failed",
                  agent_id: agent.id,
                  reason: reason,
                  state: agent
                )

                error
            end
          end

          def act(%__MODULE__{} = agent, attrs \\ %{}) do
            with {:ok, updated} <- set(agent, attrs),
                 # No need to validate again, we already did that in set/2
                 {:ok, plan_frame} <- plan(updated),
                 {:ok, final_state} <- run(plan_frame) do
              {:ok, final_state}
            end
          end

          defoverridable plan: 1

        {:error, error} ->
          Logger.warning("Invalid configuration given to use Jido.Agent: #{error}")

          error
          |> Agent.format_config_error()
          |> Error.config_error()
          |> OK.failure()
      end
    end
  end

  @spec format_config_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_config_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    formatted = "Invalid configuration given to use Jido.Agent: #{message}"
    formatted
  end

  def format_config_error(%NimbleOptions.ValidationError{keys_path: keys_path, message: message}) do
    formatted =
      "Invalid configuration given to use Jido.Agent for key #{inspect(keys_path)}: #{message}"

    formatted
  end

  def format_config_error(error) when is_binary(error) do
    error
  end

  def format_config_error(error) do
    inspect(error)
  end

  @spec format_validation_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_validation_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    formatted = "Invalid parameters for Agent: #{message}"
    formatted
  end

  def format_validation_error(%NimbleOptions.ValidationError{
        keys_path: keys_path,
        message: message
      }) do
    formatted = "Invalid parameters for Agent at #{inspect(keys_path)}: #{message}"
    formatted
  end

  def format_validation_error(error) when is_binary(error) do
    error
  end

  def format_validation_error(error) do
    inspect(error)
  end
end
