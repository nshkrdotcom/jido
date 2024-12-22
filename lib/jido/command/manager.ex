defmodule Jido.Command.Manager do
  @moduledoc """
  Manages command registration and dispatch for Agents.

  The Command Manager maintains an immutable state of registered commands
  and their specifications, handling validation and dispatch of commands
  to the appropriate handlers.

  ## Usage

      # Create a new manager
      manager = Manager.new()

      # Register command modules
      {:ok, manager} = Manager.register(manager, MyApp.ChatCommand)
      {:ok, manager} = Manager.register(manager, MyApp.ImageCommand)

      # Dispatch commands
      {:ok, actions} = Manager.dispatch(manager, :generate_text, agent, %{
        prompt: "Hello!"
      })

  ## Command Validation

  All commands are validated at registration time:
  - Command names must be unique across all modules
  - Command specs must include description and schema
  - Parameter schemas are validated using NimbleOptions

  ## Error Handling

  The manager provides detailed error messages for:
  - Invalid command specifications
  - Duplicate command registration
  - Missing commands
  - Invalid parameters
  - Command execution failures
  """

  use TypedStruct
  alias Jido.Error
  require Logger

  @type command_entry :: {module(), keyword()}
  @type dispatch_error ::
          {:error, :command_not_found | :invalid_params | :execution_failed, String.t()}

  @type command_info :: %{
          module: module(),
          description: String.t(),
          schema: NimbleOptions.t() | nil
        }

  typedstruct enforce: true do
    @typedoc """
    Manager state containing:
    - commands: Map of command names to their full specifications
    """
    field(:commands, %{optional(atom()) => command_info}, default: %{})
  end

  @doc """
  Creates a new Manager instance
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Sets up a new Command Manager with the given command modules.
  Optionally registers the Default command set first if specified.

  ## Parameters
    - modules: List of command modules to register
    - opts: Options for setup
      - register_default: Whether to register Jido.Commands.Default first (default: true)

  ## Returns
    - `{:ok, manager}` - Successfully initialized manager
    - `{:error, reason}` - Error during initialization
  """
  @spec setup([module()], keyword()) :: {:ok, t()} | {:error, String.t()}
  def setup(modules, opts \\ []) when is_list(modules) do
    register_default = Keyword.get(opts, :register_default, true)
    manager = new()

    register_modules = fn modules, manager ->
      Enum.reduce_while(modules, {:ok, manager}, fn module, {:ok, acc} ->
        case register(acc, module) do
          {:ok, updated} ->
            {:cont, {:ok, updated}}

          {:error, reason} ->
            Logger.warning("Failed to register command module",
              module: module,
              reason: reason
            )

            {:halt, {:error, reason}}
        end
      end)
    end

    with {:ok, manager} <-
           if(register_default,
             do: register(manager, Jido.Commands.Default),
             else: {:ok, manager}
           ),
         {:ok, manager} <- register_modules.(modules, manager) do
      {:ok, manager}
    end
  end

  @doc """
  Registers a command module with the manager.
  Validates command specifications and stores them for dispatch.

  Returns {:ok, updated_manager} or {:error, reason}
  """
  @spec register(t(), module()) :: {:ok, t()} | {:error, String.t()}
  def register(%__MODULE__{} = manager, command_module) when is_atom(command_module) do
    with raw_commands when is_list(raw_commands) <- normalize_commands(command_module.commands()),
         {:ok, validated} <- validate_command_specs(raw_commands),
         {:ok, manager} <- register_commands(manager, command_module, validated) do
      {:ok, manager}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, "Invalid command specification: #{inspect(error)}"}
    end
  end

  @doc """
  Dispatches a command to its registered handler.

  ## Parameters
    - manager: The Manager state
    - command: Atom name of command to execute
    - agent: Current Agent state
    - params: Command parameters (will be validated)

  ## Returns
    - `{:ok, actions}` - List of actions to execute
    - `{:error, reason}` - Detailed error description

  ## Examples

      iex> Manager.dispatch(manager, :generate_text, agent, %{
      ...>   prompt: "Hello!"
      ...> })
      {:ok, [{TextGeneration, %{prompt: "Hello!"}}]}

      iex> Manager.dispatch(manager, :unknown, agent, %{})
      {:error, :command_not_found, "Command :unknown not found"}
  """
  @spec dispatch(t(), atom(), Jido.Agent.t(), map()) ::
          {:ok, [Jido.Agent.action()]} | dispatch_error()
  def dispatch(%__MODULE__{} = manager, command, agent, params \\ %{}) do
    case Map.get(manager.commands, command) do
      %{module: module, schema: schema} = _info ->
        with {:ok, validated_params} <- validate_params(schema, params),
             {:ok, actions} <- dispatch_command(module, command, agent, validated_params) do
          {:ok, actions}
        end

      nil ->
        {:error, :command_not_found, "Command #{inspect(command)} not found"}
    end
  end

  @doc """
  Returns list of registered commands with their specifications
  """
  @spec registered_commands(t()) :: [{atom(), keyword()}]
  def registered_commands(%__MODULE__{} = manager) do
    manager.commands
    |> Enum.map(fn {name, info} ->
      {name, Map.take(info, [:description, :module])}
    end)
  end

  @doc """
  Returns list of registered command modules
  """
  @spec registered_modules(t()) :: [module()]
  def registered_modules(%__MODULE__{} = manager) do
    manager.commands
    |> Map.values()
    |> Enum.map(& &1.module)
    |> Enum.uniq()
  end

  # Private helpers
  defp normalize_commands(commands) do
    Enum.map(commands, fn
      command when is_atom(command) ->
        {command, [description: "No description provided", schema: []]}

      {name, specs} when is_atom(name) and is_list(specs) ->
        {name, specs}
    end)
  end

  defp validate_command_specs(commands) do
    commands
    |> Enum.map(fn {name, spec} ->
      case validate_single_command(name, spec) do
        {:ok, validated} -> {:ok, {name, validated}}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> collect_validation_results()
  end

  defp validate_single_command(name, spec) do
    description = spec[:description] || "No description provided"

    case spec[:schema] do
      nil ->
        {:ok, %{description: description, schema: nil}}

      [] ->
        {:ok, %{description: description, schema: nil}}

      %NimbleOptions{} = schema ->
        {:ok, %{description: description, schema: schema}}

      schema when is_list(schema) ->
        try do
          nimble_schema = NimbleOptions.new!(schema)
          {:ok, %{description: description, schema: nimble_schema}}
        rescue
          e in ArgumentError ->
            {:error, "Invalid schema for command #{name}: #{Exception.message(e)}"}
        end

      invalid ->
        {:error, "Invalid schema type for command #{name}: #{inspect(invalid)}"}
    end
  end

  defp collect_validation_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, entry}, {:ok, acc} -> {:cont, {:ok, [entry | acc]}}
      {:error, reason}, _ -> {:halt, {:error, reason}}
    end)
  end

  defp register_commands(manager, module, commands) do
    commands
    |> Enum.reduce_while({:ok, manager}, fn {name, spec}, {:ok, acc} ->
      case Map.get(acc.commands, name) do
        nil ->
          command_info = Map.put(spec, :module, module)
          updated = %{acc | commands: Map.put(acc.commands, name, command_info)}
          {:cont, {:ok, updated}}

        %{module: existing_module} ->
          {:halt, {:error, "Command #{name} already registered by #{inspect(existing_module)}"}}
      end
    end)
  end

  defp validate_params(nil, params), do: {:ok, params}

  defp validate_params(schema, params) do
    case NimbleOptions.validate(Map.to_list(params), schema) do
      {:ok, validated} ->
        {:ok, Map.new(validated)}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, :invalid_params, Error.format_nimble_validation_error(error, "Command")}
    end
  end

  defp dispatch_command(module, command, agent, params) do
    case module.handle_command(command, agent, params) do
      {:ok, _actions} = ok ->
        ok

      {:error, reason} ->
        Logger.warning("Command execution failed",
          command: command,
          module: module,
          reason: inspect(reason)
        )

        {:error, :execution_failed, "Command execution failed: #{inspect(reason)}"}
    end
  end
end
