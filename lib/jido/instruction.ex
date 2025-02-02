defmodule Jido.Instruction do
  @moduledoc """
  Represents a single instruction to be executed by a Runner.  An instruction consists of an action module and optional parameters.

  Instructions are the basic unit of execution in the Jido system. They wrap an action module
  with its parameters and execution context, allowing the Runner to execute them in a
  standardized way.

  ## Fields

  - `:action` - The action module to execute (required)
  - `:params` - Map of parameters to pass to the action (default: %{})
  - `:context` - Map of execution context data (default: %{})
  - `:opts` - Keyword list of options (default: [])

  ## Instruction Shorthand Formats

  Instructions can be specified in several formats:

  - Action module name:
      `MyApp.Actions.DoSomething`

  - Tuple of action and params:
      `{MyApp.Actions.DoSomething, %{value: 42}}`

  - Lists of instructions:
      `[MyApp.Actions.DoSomething, {MyApp.Actions.ProcessData, %{data: "input"}}]`

  - Full instruction struct:
      ```
      %Instruction{
        action: MyApp.Actions.DoSomething,
        params: %{value: 42}
      }
      ```

  Shorthand formats are for conveinence only and will be normalized to the full instruction struct.

  ## Examples

      # Create a basic instruction
      %Instruction{
        action: MyApp.Actions.DoSomething,
        params: %{value: 42}
      }

      # With context
      %Instruction{
        action: MyApp.Actions.ProcessData,
        params: %{data: "input"},
        context: %{user_id: 123}
      }

      # Using shorthand action name
      MyApp.Actions.DoSomething

      # Using tuple shorthand
      {MyApp.Actions.ProcessData, %{data: "input"}}

  Instructions are typically created by the Agent when processing commands, and then
  executed by a Runner module like `Jido.Runner.Simple` or `Jido.Runner.Chain`.
  """
  alias Jido.Error
  alias Jido.Instruction
  use ExDbug, enabled: false
  @decorate_all dbug()
  use TypedStruct

  @type action_module :: module()
  @type action_params :: map()
  @type action_tuple :: {action_module(), action_params()}
  @type instruction :: action_module() | action_tuple() | t()
  @type instruction_list :: [instruction()]

  typedstruct do
    field(:id, String.t(), default: UUID.uuid4())
    field(:action, module(), enforce: true)
    field(:params, map(), default: %{})
    field(:context, map(), default: %{})
    field(:opts, keyword(), default: [])
    field(:correlation_id, String.t(), default: nil)
  end

  @doc """
  Creates a new Instruction struct from a map or keyword list of attributes.
  Returns the struct directly or raises an error.

  ## Parameters
    * `attrs` - Map or keyword list containing instruction attributes:
      * `:action` - Action module (required)
      * `:params` - Map of parameters (optional, default: %{})
      * `:context` - Context map (optional, default: %{})
      * `:opts` - Keyword list of options (optional, default: [])

  ## Returns
    * `%Instruction{}` - Successfully created instruction

  ## Raises
    * `Jido.Error` - If action is missing or invalid

  ## Examples

      iex> Instruction.new!(%{action: MyAction, params: %{value: 1}})
      %Instruction{action: MyAction, params: %{value: 1}}

      iex> Instruction.new!(action: MyAction)
      %Instruction{action: MyAction}

      iex> Instruction.new!(%{params: %{value: 1}})
      ** (Jido.Error) missing action
  """
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, instruction} ->
        instruction

      {:error, reason} ->
        {:error,
         Error.validation_error("Invalid instruction configuration", %{
           reason: reason
         })}
    end
  end

  @doc """
  Creates a new Instruction struct from a map or keyword list of attributes.

  ## Parameters
    * `attrs` - Map or keyword list containing instruction attributes:
      * `:action` - Action module (required)
      * `:params` - Map of parameters (optional, default: %{})
      * `:context` - Context map (optional, default: %{})
      * `:opts` - Keyword list of options (optional, default: [])
      * `:id` - String identifier (optional, defaults to UUID)
      * `:correlation_id` - String correlation ID (optional)

  ## Returns
    * `{:ok, %Instruction{}}` - Successfully created instruction
    * `{:error, :missing_action}` - If action is not provided
    * `{:error, :invalid_action}` - If action is not a module

  ## Examples

      iex> Instruction.new(%{action: MyAction, params: %{value: 1}})
      {:ok, %Instruction{action: MyAction, params: %{value: 1}}}

      iex> Instruction.new(action: MyAction)
      {:ok, %Instruction{action: MyAction}}

      iex> Instruction.new(%{params: %{value: 1}})
      {:error, :missing_action}
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, :missing_action | :invalid_action}
  def new(attrs) when is_list(attrs) do
    new(Map.new(attrs))
  end

  def new(%{action: action} = attrs) when is_atom(action) do
    {:ok,
     %__MODULE__{
       id: Map.get(attrs, :id, UUID.uuid4()),
       action: action,
       params: Map.get(attrs, :params, %{}),
       context: Map.get(attrs, :context, %{}),
       opts: Map.get(attrs, :opts, []),
       correlation_id: Map.get(attrs, :correlation_id)
     }}
  end

  def new(%{action: _}), do: {:error, :invalid_action}
  def new(_), do: {:error, :missing_action}

  @doc """
  Normalizes instruction shorthand input into instruction structs. Accepts a variety of input formats
  and returns a list of normalized instruction structs.

  ## Parameters
    * `input` - One of:
      * Single instruction struct (%Instruction{})
      * List of instruction structs
      * Single action module
      * Action tuple {module, params}
      * List of actions/tuples/instructions
    * `context` - Optional context map to merge into all instructions (default: %{})
    * `opts` - Optional keyword list of options (default: [])

  ## Returns
    * `{:ok, [%Instruction{}]}` - List of normalized instruction structs
    * `{:error, term()}` - If normalization fails
  """
  @spec normalize(instruction() | instruction_list(), map(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def normalize(input, context \\ %{}, opts \\ [])

  # Handle lists by recursively normalizing each element
  def normalize(instructions, context, opts) when is_list(instructions) do
    # Check for nested lists first
    if Enum.any?(instructions, &is_list/1) do
      {:error,
       Error.execution_error("Invalid instruction format: nested lists are not allowed", %{
         instructions: instructions
       })}
    else
      context = context || %{}

      instructions
      |> Enum.reduce_while({:ok, []}, fn instruction, {:ok, acc} ->
        case normalize(instruction, context, opts) do
          {:ok, [normalized]} -> {:cont, {:ok, [normalized | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, list} -> {:ok, Enum.reverse(list)}
        error -> error
      end
    end
  end

  # Already normalized instruction - just merge context and opts
  def normalize(%__MODULE__{} = instruction, context, opts) do
    context = context || %{}
    merged_opts = if Enum.empty?(instruction.opts), do: opts, else: instruction.opts
    {:ok, [%{instruction | context: Map.merge(instruction.context, context), opts: merged_opts}]}
  end

  # Single action module
  def normalize(action, context, opts) when is_atom(action) do
    context = context || %{}
    {:ok, [new!(%{action: action, params: %{}, context: context, opts: opts})]}
  end

  # Action tuple with params
  def normalize({action, params}, context, opts) when is_atom(action) do
    context = context || %{}

    case normalize_params(params) do
      {:ok, normalized_params} ->
        {:ok, [new!(%{action: action, params: normalized_params, context: context, opts: opts})]}

      error ->
        error
    end
  end

  # Invalid format
  def normalize(invalid, _context, _opts) do
    {:error, Error.execution_error("Invalid instruction format", %{instruction: invalid})}
  end

  @doc """
  Validates that all instructions use allowed actions.

  ## Parameters
    * `instructions` - List of instruction structs
    * `allowed_actions` - List of allowed action modules

  ## Returns
    * `:ok` - All actions are allowed
    * `{:error, term()}` - If any action is not allowed

  ## Examples
      iex> instructions = [%Instruction{action: MyAction}, %Instruction{action: OtherAction}]
      iex> Instruction.validate_allowed_actions(instructions, [MyAction])
      {:error, "Actions not allowed: OtherAction"}

      iex> instructions = [%Instruction{action: MyAction}]
      iex> Instruction.validate_allowed_actions(instructions, [MyAction])
      :ok
  """
  @spec validate_allowed_actions(t() | [t()], [module()]) :: :ok | {:error, term()}
  def validate_allowed_actions(%Instruction{} = instruction, allowed_actions) do
    validate_allowed_actions([instruction], allowed_actions)
  end

  def validate_allowed_actions(instructions, allowed_actions) when is_list(instructions) do
    unregistered =
      instructions
      |> Enum.map(& &1.action)
      |> Enum.reject(&(&1 in allowed_actions))

    if Enum.empty?(unregistered) do
      :ok
    else
      unregistered_str = Enum.join(unregistered, ", ")

      {:error,
       Error.config_error("Actions not allowed: #{unregistered_str}", %{
         actions: unregistered,
         allowed_actions: allowed_actions
       })}
    end
  end

  # Private helpers

  defp normalize_params(nil), do: {:ok, %{}}
  defp normalize_params(params) when is_map(params), do: {:ok, params}

  defp normalize_params(invalid) do
    {:error,
     Error.execution_error(
       "Invalid params format. Params must be a map.",
       %{
         params: invalid,
         expected_format: "%{key: value}"
       }
     )}
  end
end
