defmodule Jido.Action.Directives do
  @moduledoc """
  A collection of actions that are used to control the behavior of the agent.

  This module provides a set of simple, reusable actions:
  - EnqueueAction: Enqueues another action based on params
  - RegisterAction: Registers a new action module
  - DeregisterAction: Deregisters an existing action module

  Each action is implemented as a separate submodule and follows the Jido.Action behavior.
  """

  alias Jido.Action

  defmodule EnqueueAction do
    @moduledoc false
    use Action,
      name: "enqueue_action",
      description: "Enqueues another action based on params",
      schema: [
        action: [type: :atom, required: true],
        params: [type: :map, default: %{}]
      ]

    def run(%{action: action, params: params}, _context) do
      directive = %Jido.Agent.Directive.EnqueueDirective{
        action: action,
        params: params,
        context: %{}
      }

      {:ok, directive}
    end
  end

  defmodule RegisterAction do
    @moduledoc false
    use Action,
      name: "register_action",
      description: "Registers a new action module",
      schema: [
        action_module: [type: :atom, required: true]
      ]

    def run(%{action_module: action_module}, _context) do
      directive = %Jido.Agent.Directive.RegisterActionDirective{
        action_module: action_module
      }

      {:ok, directive}
    end
  end

  defmodule DeregisterAction do
    @moduledoc false
    use Action,
      name: "deregister_action",
      description: "Deregisters an existing action module",
      schema: [
        action_module: [type: :atom, required: true]
      ]

    def run(%{action_module: action_module}, _context) do
      directive = %Jido.Agent.Directive.DeregisterActionDirective{
        action_module: action_module
      }

      {:ok, directive}
    end
  end
end
