# Actions Overview

_Part of the "Actions" section in the documentation._

This guide introduces the Actions system, which is the core mechanism for defining agent capabilities. It explains what actions are, how they work, and their role in enabling agent behavior and decision-making.

## Overview

Actions in Jido are pure, stateless functions that encapsulate business logic and can be composed into complex workflows. They provide a clean, functional approach to defining operations while supporting validation, error handling, and compensation.

### Core Principles

1. **Pure Functions**

   - Stateless execution
   - Predictable outcomes
   - Easy to test and reason about

2. **Composability**

   - Chain multiple actions
   - Parallel execution
   - Error propagation

3. **Safety**
   - Parameter validation
   - Error compensation
   - Timeout handling

## Implementation

### Basic Action Structure

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action

  @type order :: %{
    id: String.t(),
    items: [String.t()],
    total: Decimal.t()
  }

  @type result :: %{
    order_id: String.t(),
    status: :processed | :failed,
    processed_at: DateTime.t()
  }

  @doc """
  Process an order with the given parameters.
  """
  @spec run(order(), map()) :: {:ok, result()} | {:error, term()}
  def run(order, _context) do
    with {:ok, validated} <- validate_order(order),
         {:ok, processed} <- process_items(validated) do
      {:ok, %{
        order_id: validated.id,
        status: :processed,
        processed_at: DateTime.utc_now()
      }}
    end
  end

  @impl true
  def on_error(error, order, _context, _opts) do
    Logger.error("Failed to process order: #{inspect(error)}")
    rollback_order(order)
  end

  # Private Helpers

  defp validate_order(order) do
    NimbleOptions.validate(order, [
      id: [type: :string, required: true],
      items: [type: {:list, :string}, required: true],
      total: [type: :decimal, required: true]
    ])
  end

  defp process_items(%{items: items} = order) do
    # Process each item in the order
    results = Enum.map(items, &process_item/1)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, order}
    else
      {:error, :item_processing_failed}
    end
  end

  defp process_item(item) do
    # Simulate item processing
    if valid_item?(item) do
      {:ok, item}
    else
      {:error, :invalid_item}
    end
  end

  defp rollback_order(order) do
    # Implement compensation logic
    Logger.info("Rolling back order: #{order.id}")
    :ok
  end
end
```

### Workflow Composition

```elixir
defmodule MyApp.Workflows.OrderProcessing do
  use Jido.Workflow

  alias MyApp.Actions.{
    ValidateOrder,
    ProcessPayment,
    UpdateInventory,
    NotifyCustomer
  }

  @doc """
  Process an order through multiple steps.
  """
  def execute(order) do
    Jido.Workflow.Chain.new()
    |> Chain.add(ValidateOrder, order)
    |> Chain.add(ProcessPayment, %{amount: order.total})
    |> Chain.add_concurrent([
      {UpdateInventory, %{items: order.items}},
      {NotifyCustomer, %{order_id: order.id}}
    ])
    |> Chain.run()
  end

  @doc """
  Process orders in parallel with a worker pool.
  """
  def process_batch(orders) do
    orders
    |> Task.async_stream(&execute/1, max_concurrency: 5)
    |> Enum.reduce(%{success: [], failure: []}, fn
      {:ok, {:ok, result}}, acc ->
        %{acc | success: [result | acc.success]}
      {:ok, {:error, _} = error}, acc ->
        %{acc | failure: [error | acc.failure]}
    end)
  end
end
```

## Advanced Features

### Parameter Validation

```elixir
defmodule MyApp.Actions.CreateUser do
  use Jido.Action

  @schema [
    email: [
      type: :string,
      required: true,
      format: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
    ],
    name: [
      type: :string,
      required: true,
      length: [min: 2, max: 100]
    ],
    role: [
      type: :atom,
      values: [:admin, :user],
      default: :user
    ]
  ]

  def run(params, _context) do
    with {:ok, validated} <- NimbleOptions.validate(params, @schema),
         {:ok, user} <- create_user(validated) do
      {:ok, user}
    end
  end
end
```

### Error Compensation

```elixir
defmodule MyApp.Actions.TransferFunds do
  use Jido.Action

  def run(%{from: from, to: to, amount: amount}, context) do
    with {:ok, _} <- debit_account(from, amount),
         {:ok, _} <- credit_account(to, amount) do
      {:ok, %{status: :completed}}
    end
  end

  def on_error(:credit_failed, %{from: from, amount: amount}, _context, _opts) do
    # Compensate for failed credit by reversing the debit
    case refund_account(from, amount) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:compensation_failed, reason}}
    end
  end
end
```

### Timeout Handling

```elixir
defmodule MyApp.Actions.ProcessLongRunning do
  use Jido.Action

  def run(params, context) do
    Task.async(fn ->
      # Long-running operation
      Process.sleep(5000)
      {:ok, :completed}
    end)
    |> Task.await(context[:timeout] || 10_000)
  end

  def on_timeout(_params, _context) do
    Logger.warn("Action timed out")
    {:error, :timeout}
  end
end
```

## Testing & Verification

### Unit Tests

```elixir
defmodule MyApp.Actions.ProcessOrderTest do
  use ExUnit.Case

  alias MyApp.Actions.ProcessOrder

  describe "run/2" do
    test "processes valid order" do
      order = %{
        id: "order-123",
        items: ["item-1", "item-2"],
        total: Decimal.new("100.00")
      }

      assert {:ok, result} = ProcessOrder.run(order, %{})
      assert result.status == :processed
      assert result.order_id == order.id
    end

    test "handles invalid order" do
      order = %{id: "order-123"} # Missing required fields

      assert {:error, _} = ProcessOrder.run(order, %{})
    end
  end
end
```

### Property-Based Tests

```elixir
defmodule MyApp.Actions.ProcessOrderPropertyTest do
  use ExUnit.Case
  use PropCheck

  property "processes valid orders of any size" do
    forall order <- valid_order() do
      case ProcessOrder.run(order, %{}) do
        {:ok, result} ->
          result.order_id == order.id and
          result.status == :processed
        _ ->
          false
      end
    end
  end

  # Generators

  def valid_order do
    let {id, items, total} <- {
      string(:alphanumeric),
      list(string(:alphanumeric)),
      decimal(2)
    } do
      %{
        id: id,
        items: items,
        total: Decimal.new(total)
      }
    end
  end
end
```

## Production Readiness

### Configuration

```elixir
# config/runtime.exs
config :my_app, MyApp.Workflows,
  max_concurrency: 10,
  timeout: :timer.seconds(30),
  retry: [
    max_attempts: 3,
    base_backoff: :timer.seconds(1),
    max_backoff: :timer.seconds(30)
  ]
```

### Monitoring

1. **Telemetry Events**

   ```elixir
   :telemetry.attach(
     "workflow-metrics",
     [:jido, :workflow, :execute],
     &MyApp.Metrics.handle_workflow_event/4,
     nil
   )
   ```

2. **Performance Tracking**

   ```elixir
   def track_execution_time(action, params) do
     {time, result} = :timer.tc(fn ->
       action.run(params, %{})
     end)

     :telemetry.execute(
       [:jido, :action, :execute],
       %{duration: time},
       %{action: action, params: params}
     )

     result
   end
   ```

### Common Issues

1. **Timeouts**

   - Set appropriate timeouts for actions
   - Implement proper cleanup
   - Use async operations for long-running tasks

2. **Resource Management**

   - Monitor worker pool utilization
   - Implement backpressure
   - Handle cleanup in compensation

3. **Error Handling**
   - Implement proper compensation
   - Log detailed error information
   - Consider retry strategies

## Best Practices

1. **Action Design**

   - Keep actions focused and small
   - Validate all inputs
   - Handle all error cases

2. **Workflow Composition**

   - Use proper concurrency patterns
   - Implement proper error handling
   - Consider resource constraints

3. **Testing**

   - Write comprehensive unit tests
   - Use property-based testing
   - Test concurrent execution

4. **Production**
   - Monitor execution times
   - Track error rates
   - Implement circuit breakers

## Further Reading

- [Agent Documentation](../agents/overview.md)
- [Signal Routing](../signals/overview.md)
- [Error Handling](../practices/error-handling.md)
- [Advanced Patterns](../practices/advanced-patterns.md)
