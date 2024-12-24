defmodule JidoTest.TestAgents do
  @moduledoc false

  defmodule BasicActions do
    @moduledoc false
    use Jido.Action,
      name: "basic_default",
      description: "Default action for testing",
      schema: []

    @impl true
    def run(_params, _context) do
      {:ok, %{message: "Default action"}}
    end
  end

  defmodule NoSchemaAgent do
    @moduledoc false
    use Jido.Agent,
      name: "NoSchemaAgent",
      actions: [JidoTest.TestActions.BasicAction]
  end

  defmodule BasicAgent do
    @moduledoc false
    use Jido.Agent,
      name: "BasicAgent",
      actions: [JidoTest.TestActions.BasicAction, JidoTest.TestActions.NoSchema],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100]
      ]

    @impl true
    def on_before_plan(_agent, _action, _params) do
      {:ok, {JidoTest.TestActions.BasicAction, %{value: 1}}}
    end
  end

  defmodule SimpleAgent do
    @moduledoc false
    alias JidoTest.TestActions.{
      BasicAction,
      NoSchema,
      DelayAction,
      RawResultAction,
      CompensateAction,
      RetryAction
    }

    use Jido.Agent,
      name: "SimpleBot",
      actions: [
        BasicAction,
        NoSchema,
        RawResultAction,
        CompensateAction,
        RetryAction,
        DelayAction
      ],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100]
      ]
  end

  defmodule AdvancedAgent do
    @moduledoc false
    use Jido.Agent,
      name: "AdvancedAgent",
      description: "Test agent with hooks",
      category: "test",
      tags: ["test", "hooks"],
      vsn: "1.0.0",
      actions: [
        JidoTest.TestActions.Add,
        JidoTest.TestActions.Multiply,
        JidoTest.TestActions.DelayAction,
        JidoTest.TestActions.ContextAction
      ],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100],
        has_reported: [type: :boolean, default: false]
      ]

    # Add hook implementations for testing
    @impl true
    def on_before_validate_state(state) do
      # Add a timestamp during validation
      {:ok, Map.put(state, :last_validated, System.system_time(:second))}
    end

    @impl true
    def on_before_plan(_agent, :special, _params) do
      # Transform special action into basic with default value
      {:ok, {JidoTest.TestActions.BasicAction, %{value: 1}}}
    end

    # Handle default case
    @impl true
    def on_before_plan(_agent, action, params) do
      {:ok, {action, params}}
    end
  end

  defmodule SyscallAgent do
    @moduledoc false
    alias JidoTest.TestActions.{
      StreamingAction,
      ConcurrentAction,
      LongRunningAction,
      SpawnerAction
    }

    use Jido.Agent,
      name: "SyscallAgent",
      description: "Test agent for system calls",
      category: "test",
      tags: ["test", "syscall"],
      vsn: "1.0.0",
      actions: [
        StreamingAction,
        ConcurrentAction,
        LongRunningAction,
        SpawnerAction
      ],
      schema: [
        processes: [type: {:map, :pid, :any}, default: %{}],
        subscriptions: [type: {:list, :string}, default: []],
        checkpoints: [type: {:map, :any, :map}, default: %{}],
        location: [type: :atom, default: :home]
      ]
  end
end
