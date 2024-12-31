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
  - `:result` - Result of executing the instruction (default: nil)

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
  use TypedStruct

  @type action_module :: module()
  @type action_params :: map()
  @type action_tuple :: {action_module(), action_params()}
  @type instruction :: action_module() | action_tuple() | t()
  @type instruction_list :: [instruction()]

  typedstruct enforce: true do
    field(:action, module(), enforce: true)
    field(:params, map(), default: %{})
    field(:context, map(), default: %{})
    field(:result, term(), default: nil)
  end
end
