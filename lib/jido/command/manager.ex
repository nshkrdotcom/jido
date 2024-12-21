defmodule Jido.CommandManager do
  @moduledoc """
  Manages command registration and dispatch for Agents.

  The CommandManager maintains an immutable state of registered commands
  and their specifications, handling validation and dispatch of commands
  to the appropriate handlers.

  ## Usage

      # Create a new manager
      manager = CommandManager.new()

      # Register command modules
      {:ok, manager} = CommandManager.register(manager, MyApp.ChatCommand)
      {:ok, manager} = CommandManager.register(manager, MyApp.ImageCommand)

      # Dispatch commands
      {:ok, actions} = CommandManager.dispatch(manager, :generate_text, agent, %{
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

  typedstruct enforce: true do
    @typedoc """
    CommandManager state containing:
    - modules: Map of registered command modules
    - commands: Map of command names to {module, spec} tuples
    - schemas: Map of command validation schemas
    """
    field(:modules, %{optional(module()) => [{atom(), keyword()}]}, default: %{})
    field(:commands, %{optional(atom()) => command_entry}, default: %{})
    field(:schemas, %{optional(atom()) => NimbleOptions.t()}, default: %{})
  end

  @command_spec_schema NimbleOptions.new!(
                         description: [
                           type: :string,
                           required: true,
                           doc: "Description of what the command does"
                         ],
                         schema: [
                           type: :keyword_list,
                           required: true,
                           doc: "NimbleOptions schema for command parameters"
                         ]
                       )

  @doc """
  Creates a new CommandManager instance
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Registers a command module with the manager.
  Validates command specifications and stores them for dispatch.

  Returns {:ok, updated_manager} or {:error, reason}
  """
  @spec register(t(), module()) :: {:ok, t()} | {:error, String.t()}
  def register(%__MODULE__{} = manager, command_module) when is_atom(command_module) do
    with commands when is_list(commands) <- command_module.commands(),
         {:ok, validated} <- validate_command_specs(commands),
         {:ok, manager} <- add_module(manager, command_module, validated),
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
    - manager: The CommandManager state
    - command: Atom name of command to execute
    - agent: Current Agent state
    - params: Command parameters (will be validated)

  ## Returns
    - `{:ok, actions}` - List of actions to execute
    - `{:error, reason}` - Detailed error description

  ## Examples

      iex> CommandManager.dispatch(manager, :generate_text, agent, %{
      ...>   prompt: "Hello!"
      ...> })
      {:ok, [{TextGeneration, %{prompt: "Hello!"}}]}

      iex> CommandManager.dispatch(manager, :unknown, agent, %{})
      {:error, :command_not_found, "Command :unknown not found"}
  """
  @spec dispatch(t(), atom(), Jido.Agent.t(), map()) ::
          {:ok, [Jido.Agent.action()]} | dispatch_error()
  def dispatch(%__MODULE__{} = manager, command, agent, params \\ %{}) do
    case Map.get(manager.commands, command) do
      {module, _spec} ->
        with {:ok, schema} <- Map.fetch(manager.schemas, command),
             {:ok, validated_params} <- validate_params(schema, params),
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
    Enum.map(manager.commands, fn {name, {_mod, spec}} -> {name, spec} end)
  end

  @doc """
  Returns list of registered command modules
  """
  @spec registered_modules(t()) :: [module()]
  def registered_modules(%__MODULE__{} = manager) do
    Map.keys(manager.modules)
  end

  # Private helpers

  defp validate_command_specs(commands) do
    commands
    |> Enum.map(fn {name, spec} ->
      case NimbleOptions.validate(spec, @command_spec_schema) do
        {:ok, validated} -> {:ok, {name, validated}}
        {:error, error} -> {:error, "Invalid command #{name}: #{Exception.message(error)}"}
      end
    end)
    |> collect_validation_results()
  end

  defp collect_validation_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, entry}, {:ok, acc} -> {:cont, {:ok, [entry | acc]}}
      {:error, reason}, _ -> {:halt, {:error, reason}}
    end)
  end

  defp add_module(manager, module, commands) do
    case Map.get(manager.modules, module) do
      nil ->
        {:ok, %{manager | modules: Map.put(manager.modules, module, commands)}}

      _existing ->
        {:error, "Module #{inspect(module)} already registered"}
    end
  end

  defp register_commands(manager, module, commands) do
    commands
    |> Enum.reduce_while({:ok, manager}, fn {name, spec}, {:ok, acc} ->
      case Map.get(acc.commands, name) do
        nil ->
          schema = NimbleOptions.new!(spec[:schema])

          updated = %{
            acc
            | commands: Map.put(acc.commands, name, {module, spec}),
              schemas: Map.put(acc.schemas, name, schema)
          }

          {:cont, {:ok, updated}}

        {existing_module, _} ->
          {:halt, {:error, "Command #{name} already registered by #{inspect(existing_module)}"}}
      end
    end)
  end

  defp validate_params(schema, params) do
    case NimbleOptions.validate(Map.to_list(params), schema) do
      {:ok, validated} ->
        {:ok, validated}

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
