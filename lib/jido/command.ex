defmodule Jido.Command do
  @moduledoc """
  Defines a Command behavior for extending Agent capabilities.

  Commands are the primary way to extend an Agent's functionality. Each Command module can
  implement multiple named commands that define sequences of Actions for the Agent to execute.

  ## Command Registration

  Commands must be registered with the Agent's Command Manager before use:

      {:ok, manager} = Manager.new() |> Manager.register(MyApp.ChatCommand)
      {:ok, agent} = Agent.new() |> Agent.set_command_manager(manager)

  ## Command Structure

  Each command requires:
  - A unique name (atom)
  - A description explaining its purpose
  - A handle_command/3 implementation that returns Actions

  ## Example Implementation

      defmodule MyApp.ChatCommand do
        use Jido.Command,
          name: "chat_command",
          description: "Handles chat-related commands",
          category: "chat",
          tags: ["conversation", "text"],
          vsn: "1.0.0"

        @impl true
        def commands do
          [
            generate_text: [
              description: "Generates a text response",
              schema: [
                prompt: [
                  type: :string,
                  required: true,
                  doc: "The input prompt for text generation"
                ],
                max_tokens: [
                  type: :integer,
                  default: 100,
                  doc: "Maximum tokens to generate"
                ]
              ]
            ]
          ]
        end

        @impl true
        def handle_command(:generate_text, agent, params) do
          actions = [
            {TextGeneration, params},
            {ResponseFormatter, format: :markdown}
          ]
          {:ok, actions}
        end
      end

  ## Error Handling

  Commands should return detailed error tuples when failures occur:

      def handle_command(:risky_command, agent, params) do
        case validate_preconditions(agent) do
          :ok -> {:ok, [{SafeAction, params}]}
          {:error, reason} ->
            {:error, "Command failed precondition check: \#{reason}"}
        end
      end

  ## Testing Commands

  See `Jido.CommandTest` for examples of testing Command implementations.
  """

  alias Jido.Error

  require OK

  use TypedStruct

  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:description, String.t())
    field(:category, String.t())
    field(:tags, [String.t()], default: [])
    field(:vsn, String.t())
  end

  @command_config_schema NimbleOptions.new!(
                           name: [
                             type: {:custom, Jido.Util, :validate_name, []},
                             required: true,
                             doc:
                               "The name of the Command. Must contain only letters, numbers, and underscores."
                           ],
                           description: [
                             type: :string,
                             required: false,
                             doc: "A description of what the Command does."
                           ],
                           category: [
                             type: :string,
                             required: false,
                             doc: "The category of the Command."
                           ],
                           tags: [
                             type: {:list, :string},
                             default: [],
                             doc: "A list of tags associated with the Command."
                           ],
                           vsn: [
                             type: :string,
                             required: false,
                             doc: "The version of the Command."
                           ]
                         )

  @type command :: atom()
  @type command_spec :: [
          description: String.t(),
          schema: NimbleOptions.schema()
        ]
  @type action :: Jido.Agent.action()
  @type error :: {:error, String.t()}

  @doc """
  Returns a list of commands that this module implements.
  Each command should have a description and schema for validation.

  ## Example

      def commands do
        [
          my_command: [
            description: "Does something useful",
            schema: [
              input: [type: :string, required: true]
            ]
          ]
        ]
      end
  """
  @callback commands() :: [{command(), command_spec()}]

  @doc """
  Handles execution of a specific command.

  ## Parameters
    - command: The command name to execute
    - agent: The current Agent state
    - params: Validated parameters for the command

  ## Returns
    - `{:ok, actions}` - List of actions to execute
    - `{:error, reason}` - Error with description

  ## Example

      def handle_command(:my_command, agent, params) do
        case preconditions_met?(agent) do
          true ->
            actions = [{MyAction, params}]
            {:ok, actions}
          false ->
            {:error, "Agent not ready"}
        end
      end
  """
  @callback handle_command(command(), Jido.Agent.t(), params :: map()) ::
              {:ok, [action()]} | error()

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@command_config_schema)

    quote location: :keep do
      @behaviour Jido.Command
      require Logger
      require OK

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]

          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn]
            }
          end

          def __command_metadata__ do
            to_json()
          end

        {:error, error} ->
          error
          |> Error.format_nimble_config_error("Command")
          |> Error.config_error()
          |> OK.failure()
      end
    end
  end
end
