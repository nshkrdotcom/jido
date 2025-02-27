defmodule Jido.Skill do
  @moduledoc """
  Defines the core behavior and structure for Jido Skills, the fundamental building blocks
  of agent capabilities in the Jido framework.

  ## Overview

  Skills encapsulate discrete sets of functionality that agents can use to accomplish tasks.
  Think of them as feature packs that give agents new abilities - similar to how a person might
  learn skills like "cooking" or "programming". Each Skill provides:

  - Signal routing and handling patterns
  - Isolated state management
  - Process supervision
  - Configuration validation
  - Runtime adaptation

  ## Core Concepts

  ### State Isolation

  Skills use schema-based state isolation to prevent different capabilities from interfering
  with each other. Each skill defines:

  - A unique `opts_key` for namespace isolation
  - Validation rules for configuration

  ### Signal Patterns

  Skills define what signals they can handle through pattern matching:

  ```elixir
  use Jido.Skill,
    name: "weather_monitor",
    signals: [
      input: ["weather.data.*", "weather.alert.**"],
      output: ["weather.alert.generated"]
    ]
  ```

  Pattern rules:
  - Exact matches: "user.created"
  - Single wildcards: "user.*.updated"
  - Multi-wildcards: "audit.**"

  ### Configuration Management

  Skills provide schema-based config validation:

  ```elixir
  config: [
    api_key: [
      type: :string,
      required: true,
      doc: "API key for weather service"
    ],
    update_interval: [
      type: :pos_integer,
      default: 60_000,
      doc: "Update interval in milliseconds"
    ]
  ]
  ```

  ### Process Supervision

  Skills can define child processes through the `child_spec/1` callback:

  ```elixir
  def child_spec(config) do
    [
      {WeatherAPI.Client, config.api_key},
      {MetricsCollector, name: config.metrics_name}
    ]
  end
  ```

  ## Usage Example

  Here's a complete skill example:

  ```elixir
  defmodule MyApp.WeatherSkill do
    use Jido.Skill,
      name: "weather_monitor",
      description: "Monitors weather conditions and generates alerts",
      category: "monitoring",
      tags: ["weather", "alerts"],
      vsn: "1.0.0",
      opts_key: :weather,
      signals: [
        input: ["weather.data.*", "weather.alert.**"],
        output: ["weather.alert.generated"]
      ],
      config: [
        api_key: [type: :string, required: true]
      ]

    def child_spec(config) do
      [
        {WeatherAPI.Client, config.api_key}
      ]
    end

    def handle_signal(%Signal{type: "weather.data.updated"} = signal) do
      # Handle weather updates
      {:ok, signal}
    end
  end
  ```

  ## Callbacks

  Skills implement these callbacks:

  - `child_spec/1` - Returns child process specifications
  - `router/0` - Returns signal routing rules
  - `handle_signal/1` - Processes incoming signals
  - `process_result/2` - Post-processes signal handling results
  - `mount/2` - Mounts the skill to an agent

  ## Behavior

  The Skill behavior enforces a consistent interface:

  ```elixir
  @callback child_spec(config :: map()) :: Supervisor.child_spec() | [Supervisor.child_spec()]
  @callback router() :: [map()]
  @callback handle_signal(signal :: Signal.t()) :: {:ok, Signal.t()} | {:error, term()}
  @callback process_result(signal :: Signal.t(), result :: term()) ::
              {:ok, term()} | {:error, term()}
  @callback mount(agent :: Jido.Agent.t(), opts :: keyword()) :: Jido.Agent.t()
  ```

  ## Configuration

  Skills validate their configuration at compile time using these fields:

  - `name` - Unique identifier (required)
  - `description` - Human-readable explanation
  - `category` - Broad classification
  - `tags` - List of searchable tags
  - `vsn` - Version string
  - `opts_key` - State namespace key
  - `signals` - Input/output patterns
  - `config` - Configuration schema

  ## Best Practices

  1. **State Isolation**
     - Use meaningful opts_key names
     - Keep state focused and minimal
     - Document state structure

  2. **Signal Design**
     - Use consistent naming patterns
     - Document signal formats
     - Consider routing efficiency

  3. **Configuration**
     - Validate thoroughly
     - Provide good defaults
     - Document all options

  4. **Process Management**
     - Supervise child processes
     - Handle crashes gracefully
     - Monitor resource usage

  ## See Also

  - `Jido.Signal` - Signal structure and validation
  - `Jido.Error` - Error handling
  - `Jido.Agent` - Agent integration
  """
  alias Jido.Signal
  alias Jido.Error
  require OK
  use TypedStruct

  @typedoc """
  Represents a skill's core structure and metadata.

  Fields:
  - `name`: Unique identifier for the skill
  - `description`: Human-readable explanation of purpose
  - `category`: Broad classification for organization
  - `tags`: List of searchable tags
  - `vsn`: Version string for compatibility
  - `opts_key`: Atom key for state namespace
  - `signals`: Input/output signal patterns
  - `config`: Configuration schema
  """
  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:description, String.t())
    field(:category, String.t())
    field(:tags, [String.t()], default: [])
    field(:vsn, String.t())
    field(:opts_key, atom())
    field(:signals, map())
    field(:config, map())
  end

  # Configuration schema validation
  @skill_config_schema NimbleOptions.new!(
                         name: [
                           type: {:custom, Jido.Util, :validate_name, []},
                           required: true,
                           doc:
                             "The name of the Skill. Must contain only letters, numbers, and underscores."
                         ],
                         description: [
                           type: :string,
                           required: false,
                           doc: "A description of what the Skill does."
                         ],
                         category: [
                           type: :string,
                           required: false,
                           doc: "The category of the Skill."
                         ],
                         tags: [
                           type: {:list, :string},
                           default: [],
                           doc: "A list of tags associated with the Skill."
                         ],
                         vsn: [
                           type: :string,
                           required: false,
                           doc: "The version of the Skill."
                         ],
                         opts_key: [
                           type: :atom,
                           required: true,
                           doc: "Atom key for state namespace isolation"
                         ],
                         opts_schema: [
                           type: :keyword_list,
                           default: [],
                           doc: "Nimble Options schema for skill options"
                         ],
                         signals: [
                           type: :map,
                           required: true,
                           doc: "Input/output signal patterns",
                           keys: [
                             input: [type: {:list, :string}, default: []],
                             output: [type: {:list, :string}, default: []]
                           ]
                         ]
                       )

  @doc """
  Implements the skill behavior and configuration validation.

  This macro:
  1. Validates configuration at compile time
  2. Defines metadata accessors
  3. Provides JSON serialization
  4. Sets up default implementations

  ## Example

      defmodule MySkill do
        use Jido.Skill,
          name: "my_skill",
          opts_key: :my_skill,
          signals: [
            input: ["my.event.*"],
            output: ["my.result.*"]
          ]
      end
  """
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@skill_config_schema)

    quote location: :keep do
      @behaviour Jido.Skill
      alias Jido.Skill
      alias Jido.Signal
      alias Jido.Instruction
      require OK

      # Validate configuration at compile time
      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          # Define metadata accessors
          @doc false
          def name, do: @validated_opts[:name]

          @doc false
          def description, do: @validated_opts[:description]

          @doc false
          def category, do: @validated_opts[:category]

          @doc false
          def tags, do: @validated_opts[:tags]

          @doc false
          def vsn, do: @validated_opts[:vsn]

          @doc false
          def opts_key, do: @validated_opts[:opts_key]

          @doc false
          def signals, do: @validated_opts[:signals]

          @doc false
          def opts_schema, do: @validated_opts[:opts_schema]

          @doc false
          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              opts_key: @validated_opts[:opts_key],
              signals: @validated_opts[:signals],
              opts_schema: @validated_opts[:opts_schema]
            }
          end

          @doc false
          def __skill_metadata__ do
            to_json()
          end

          # Default implementations
          @doc false
          def child_spec(_config), do: []

          @doc false
          def router(_opts), do: []

          @doc false
          def handle_signal(signal), do: {:ok, signal}

          @doc false
          def process_result(signal, result), do: {:ok, result}

          @doc false
          def mount(agent, _opts), do: {:ok, agent}

          defoverridable child_spec: 1,
                         router: 1,
                         handle_signal: 1,
                         process_result: 2,
                         mount: 2

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "Skill", __MODULE__)

          raise CompileError,
            description: message,
            file: __ENV__.file,
            line: __ENV__.line
      end
    end
  end

  # Behaviour callbacks
  @callback child_spec(config :: map()) :: Supervisor.child_spec() | [Supervisor.child_spec()]
  @callback router(skill_opts :: keyword()) :: [Route.t()]
  @callback handle_signal(signal :: Signal.t()) :: {:ok, Signal.t()} | {:error, term()}
  @callback process_result(signal :: Signal.t(), result :: term()) ::
              {:ok, term()} | {:error, any()}
  @callback mount(agent :: Jido.Agent.t(), opts :: keyword()) ::
              {:ok, Jido.Agent.t()} | {:error, Error.t()}

  @doc """
  Skills must be defined at compile time, not runtime.

  This function always returns an error to enforce compile-time definition.
  """
  @spec new() :: {:error, Error.t()}
  @spec new(map() | keyword()) :: {:error, Error.t()}
  def new, do: new(%{})

  @doc false
  def new(_map_or_kwlist) do
    "Skills should not be defined at runtime"
    |> Error.config_error()
    |> OK.failure()
  end

  @doc """
  Validates a skill's configuration against its schema.

  ## Parameters
  - `skill_module`: The skill module to validate
  - `config`: Configuration map to validate

  ## Returns
  - `{:ok, validated_config}`: Successfully validated config
  - `{:error, reason}`: Validation failed

  ## Example

      Skill.validate_opts(WeatherSkill, %{
        api_key: "abc123",
        interval: 1000
      })
  """
  @spec validate_opts(module(), map()) :: {:ok, map()} | {:error, Error.t()}
  def validate_opts(skill_module, config) do
    with {:ok, schema} <- get_opts_schema(skill_module) do
      NimbleOptions.validate(config, schema)
    end
  end

  @doc """
  Gets a skill's configuration schema.

  ## Parameters
  - `skill_module`: The skill module to inspect

  ## Returns
  - `{:ok, schema}`: The skill's config schema
  - `{:error, reason}`: Schema not found

  ## Example

      Skill.get_config_schema(WeatherSkill)
  """
  @spec get_opts_schema(module()) :: {:ok, map()} | {:error, Error.t()}
  def get_opts_schema(skill_module) do
    case function_exported?(skill_module, :opts_schema, 0) do
      true ->
        {:ok, skill_module.opts_schema()}

      false ->
        {:error, Error.config_error("Skill has no opts schema")}
    end
  end

  @doc """
  Validates a signal against a skill's defined patterns.

  ## Parameters
  - `signal`: The signal to validate
  - `patterns`: Map of input/output patterns

  ## Returns
  - `:ok`: Signal matches patterns
  - `{:error, reason}`: No matching patterns

  ## Example

      Skill.validate_signal(
        %Signal{type: "weather.data.updated"},
        %{input: ["weather.data.*"], output: []}
      )
  """
  @spec validate_signal(Signal.t(), map()) :: :ok | {:error, Error.t()}
  def validate_signal(%Signal{} = signal, patterns) do
    cond do
      match_any_pattern?(signal.type, patterns.input) ->
        :ok

      match_any_pattern?(signal.type, patterns.output) ->
        :ok

      true ->
        {:error, Error.validation_error("Signal type does not match any patterns")}
    end
  end

  # Private helpers
  defp match_any_pattern?(signal_type, patterns) do
    Enum.any?(patterns, &pattern_match?(signal_type, &1))
  end

  defp pattern_match?(signal_type, pattern) do
    regex = pattern_to_regex(pattern)
    String.match?(signal_type, regex)
  end

  defp pattern_to_regex(pattern) do
    pattern
    |> String.replace(".", "\\.")
    |> String.replace("*", ".*")
    |> then(&"^#{&1}$")
    |> Regex.compile!()
  end
end
