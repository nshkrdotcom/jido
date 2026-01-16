defmodule JidoTest.Fixtures do
  @moduledoc """
  Shared test fixtures for Jido test suite.

  These fixtures are commonly used across multiple test files and should be
  used instead of defining inline fixtures in individual tests.

  ## Actions

    * `IncrementAction` - Increments :counter by 1
    * `DecrementAction` - Decrements :counter by 1
    * `RecordAction` - Appends params to :messages list
    * `NoopAction` - Does nothing, returns empty map
    * `SlowAction` - Sleeps for configurable delay_ms
    * `FailingAction` - Always fails with configurable error

  ## Agents

    * `CounterAgent` - Agent with counter and messages state, routes for common actions
    * `MinimalAgent` - Bare minimum agent with no routes
  """

  # ============================================================================
  # Common Actions
  # ============================================================================

  defmodule IncrementAction do
    @moduledoc "Action that increments the :counter state field by 1"
    use Jido.Action,
      name: "increment",
      schema: [
        amount: [type: :integer, default: 1]
      ]

    def run(%{amount: amount}, context) do
      count = Map.get(context.state, :counter, 0)
      {:ok, %{counter: count + amount}}
    end
  end

  defmodule DecrementAction do
    @moduledoc "Action that decrements the :counter state field by 1"
    use Jido.Action,
      name: "decrement",
      schema: [
        amount: [type: :integer, default: 1]
      ]

    def run(%{amount: amount}, context) do
      count = Map.get(context.state, :counter, 0)
      {:ok, %{counter: count - amount}}
    end
  end

  defmodule RecordAction do
    @moduledoc "Action that appends params to the :messages state field"
    use Jido.Action,
      name: "record",
      schema: [
        message: [type: :any, required: false]
      ]

    def run(params, context) do
      messages = Map.get(context.state, :messages, [])
      message = Map.get(params, :message, params)
      {:ok, %{messages: messages ++ [message]}}
    end
  end

  defmodule NoopAction do
    @moduledoc "Action that does nothing and returns an empty map"
    use Jido.Action,
      name: "noop",
      schema: []

    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule SlowAction do
    @moduledoc "Action that sleeps for a configurable delay"
    use Jido.Action,
      name: "slow",
      schema: [
        delay_ms: [type: :integer, default: 100]
      ]

    def run(%{delay_ms: delay}, _context) do
      Process.sleep(delay)
      {:ok, %{processed: true, delay: delay}}
    end
  end

  defmodule FailingAction do
    @moduledoc "Action that always fails with a configurable error message"
    use Jido.Action,
      name: "failing",
      schema: [
        reason: [type: :string, default: "intentional failure"]
      ]

    def run(%{reason: reason}, _context) do
      {:error, reason}
    end
  end

  defmodule EmitAction do
    @moduledoc "Action that emits a signal"
    use Jido.Action,
      name: "emit",
      schema: [
        signal_type: [type: :string, default: "test.emitted"],
        signal_data: [type: :map, default: %{}]
      ]

    alias Jido.Agent.Directive

    def run(%{signal_type: type, signal_data: data}, _context) do
      signal = %{type: type, data: data}
      {:ok, %{emitted: true}, Directive.emit(signal)}
    end
  end

  # ============================================================================
  # Common Agents
  # ============================================================================

  defmodule CounterAgent do
    @moduledoc """
    Standard test agent with counter and messages state.

    Routes:
      - "increment" -> IncrementAction
      - "decrement" -> DecrementAction  
      - "record" -> RecordAction
      - "noop" -> NoopAction
      - "slow" -> SlowAction
      - "fail" -> FailingAction
      - "emit" -> EmitAction
    """
    use Jido.Agent,
      name: "counter_agent",
      description: "Test agent with counter and message tracking",
      schema: [
        counter: [type: :integer, default: 0],
        messages: [type: {:list, :any}, default: []]
      ]

    def signal_routes do
      [
        {"increment", JidoTest.Fixtures.IncrementAction},
        {"decrement", JidoTest.Fixtures.DecrementAction},
        {"record", JidoTest.Fixtures.RecordAction},
        {"noop", JidoTest.Fixtures.NoopAction},
        {"slow", JidoTest.Fixtures.SlowAction},
        {"fail", JidoTest.Fixtures.FailingAction},
        {"emit", JidoTest.Fixtures.EmitAction}
      ]
    end
  end

  defmodule MinimalAgent do
    @moduledoc "Bare minimum agent with no state schema or routes"
    use Jido.Agent,
      name: "minimal_agent"

    def signal_routes, do: []
  end
end
