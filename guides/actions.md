# Working with Workflows in Jido: Actions, Chains, and Closures

Jido's workflows system provides a robust framework for building composable, fault-tolerant business logic through Actions (discrete workflows), Chains (workflow sequences), and Closures (reusable workflow wrappers).

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Working with Actions](#working-with-actions)
3. [Workflow Chains](#workflow-chains)
4. [Workflow Closures](#workflow-closures)
5. [Advanced Features](#advanced-features)

## Core Concepts

The Jido workflows system is built on several key abstractions:

- **Actions**: Discrete, composable units of functionality with built-in validation and error handling
- **Chains**: Sequences of workflows where output flows from one workflow to the next
- **Closures**: Reusable workflow wrappers with pre-configured context and options

Rather than using exceptions, Jido employs a functional approach that offers several benefits:

- Consistent error handling through `{:ok, result}` or `{:error, reason}` tuples
- Composable workflows that can be chained together
- Explicit error paths that require handling
- No silent failures
- Better testability through monadic workflows
- Built-in parameter validation
- Standardized telemetry and monitoring

## Working with Actions

### Creating a Basic Action

Here's how to create a simple Action:

```elixir
defmodule MyApp.AddOneAction do
  use Jido.Action,
    name: "add_one",
    description: "Adds 1 to the input value",
    schema: [
      value: [type: :integer, required: true]
    ]

  @impl true
  def run(%{value: value}, _context) do
    {:ok, %{value: value + 1}}
  end
end
```

Key components:
- The `use Jido.Action` statement with required configuration
- A schema defining expected parameters
- The `run/2` callback implementation

### Action Configuration Options

When defining a Action, you can specify:

```elixir
use Jido.Action,
  name: "my_action",              # Required, must be snake_case
  description: "Description",     # Optional documentation
  category: "processing",        # Optional categorization
  tags: ["tag1", "tag2"],       # Optional tags for grouping
  vsn: "1.0.0",                 # Optional version string
  schema: [                     # Optional parameter schema
    param1: [type: :string, required: true],
    param2: [type: :integer, default: 0]
  ]
```

### Parameter Validation

Actions use NimbleOptions for parameter validation. The schema supports:

```elixir
schema: [
  string_param: [type: :string],
  integer_param: [type: :integer],
  atom_param: [type: :atom],
  boolean_param: [type: :boolean],
  list_param: [type: {:list, :string}],
  keyword_list_param: [type: :keyword_list],
  map_param: [type: :map],
  custom_param: [type: {:custom, MyModule, :validate_custom, []}]
]
```

## Workflow Chains

Chains allow you to compose multiple workflows together, where the output of one workflow becomes the input for the next.

### Basic Chaining

```elixir
alias Jido.Workflow.Chain

# Simple sequential chain
Chain.chain([
  AddOne,
  MultiplyByTwo,
  SubtractThree
], %{value: 5})

# With workflow-specific options
Chain.chain([
  AddOne,
  {MultiplyBy, [factor: 3]},
  {WriteToFile, [filename: "result.txt"]},
  SubtractThree
], %{value: 5})
```

### Chain Options

Chains support several options:

```elixir
Chain.chain(
  workflows,
  initial_params,
  async: true,                # Run the chain asynchronously
  context: %{user_id: 123},   # Context passed to each workflow
  timeout: 5000,              # Maximum execution time
  max_retries: 3,             # Retry attempts for failed workflows
  backoff: 1000               # Initial retry backoff time
)
```

### Chain Error Handling

Chains stop execution on the first error:

```elixir
case Chain.chain([Op1, Op2, Op3], params) do
  {:ok, result} ->
    # All workflows succeeded
    handle_success(result)
  
  {:error, error} ->
    # An workflow failed
    handle_error(error)
end
```

## Workflow Closures

Closures allow you to create reusable workflow wrappers with pre-configured context and options.

### Creating Closures

```elixir
alias Jido.Workflow.Closure

# Create a closure with pre-configured context
closure = Closure.closure(MyAction, 
  %{user_id: 123},           # Pre-configured context
  timeout: 5000              # Pre-configured options
)

# Use the closure multiple times
{:ok, result1} = closure.(%{value: 5})
{:ok, result2} = closure.(%{value: 10})
```

### Async Closures

```elixir
# Create an async closure
async_closure = Closure.async_closure(MyAction, 
  %{user_id: 123},
  timeout: 5000
)

# Use the async closure
async_ref = async_closure.(%{value: 5})
{:ok, result} = Jido.Workflow.await(async_ref)
```

## Running Workflows

Common workflow execution patterns:

```elixir
# Synchronous execution
{:ok, result} = Jido.Workflow.run(MyAction, %{value: 5})

# Asynchronous execution
async_ref = Jido.Workflow.run_async(MyAction, %{value: 5})
{:ok, result} = Jido.Workflow.await(async_ref)

# With context
{:ok, result} = Jido.Workflow.run(MyAction, %{value: 5}, %{user_id: 123})

# With options
{:ok, result} = Jido.Workflow.run(MyAction, %{value: 5}, %{}, 
  timeout: 5000,
  max_retries: 3,
  backoff: 1000
)
```

## Lifecycle Hooks

Workflows support optional lifecycle callbacks:

```elixir
defmodule MyAction do
  use Jido.Action,
    name: "my_action",
    schema: [value: [type: :integer, required: true]]

  # Called before parameter validation
  @impl true
  def on_before_validate_params(params) do
    {:ok, params}
  end

  # Called after parameter validation
  @impl true
  def on_after_validate_params(params) do
    {:ok, params}
  end

  # Main execution
  @impl true
  def run(params, context) do
    {:ok, %{result: params.value * 2}}
  end

  # Called after successful execution
  @impl true
  def on_after_run(result) do
    {:ok, result}
  end
end
```

## Error Handling

The system uses the `Jido.Error` module for standardized error handling:

```elixir
def run(params, _context) do
  case process_data(params) do
    {:ok, result} -> 
      {:ok, %{result: result}}
    
    {:error, reason} ->
      {:error, Error.execution_error("Processing failed: #{reason}")}
  end
end
```

Common error types:
- `:validation_error` - Invalid parameters
- `:execution_error` - Runtime execution failure
- `:timeout` - Workflow exceeded time limit
- `:config_error` - Invalid configuration

## Testing

Here's how to test workflows effectively:

```elixir
defmodule MyActionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties  # For property-based testing
  
  alias MyApp.MyAction

  test "processes valid input" do
    assert {:ok, %{result: 10}} = 
      MyAction.run(%{value: 5}, %{})
  end

  test "validates parameters" do
    assert {:error, %Error{type: :validation_error}} =
      MyAction.validate_params(%{invalid: "params"})
  end

  test "chains workflows" do
    result = Chain.chain([
      AddOne,
      {MultiplyBy, [factor: 2]}
    ], %{value: 5})
    
    assert {:ok, %{value: 12}} = result
  end

  property "handles all valid integers" do
    check all value <- integer() do
      assert {:ok, %{result: result}} = 
        MyAction.run(%{value: value}, %{})
      assert result == value * 2
    end
  end
end
```

## Best Practices

1. Keep workflows focused on a single responsibility
2. Use meaningful names and descriptions
3. Always validate input parameters
4. Return consistent result structures
5. Handle all error cases explicitly
6. Use context for cross-cutting concerns
7. Add telemetry for monitoring
8. Write comprehensive tests including property-based tests
9. Document behavior and edge cases
10. Consider retry strategies for workflows that may fail
11. Use chains for complex workflows
12. Use closures to create reusable workflow configurations

## Advanced Features

### Telemetry Integration

Workflows automatically emit telemetry events that can be used for monitoring:

- `:start` - When an workflow begins execution
- `:complete` - When an workflow successfully completes
- `:error` - When an workflow encounters an error

### Retry Mechanisms

Built-in retry support with exponential backoff:

```elixir
Jido.Workflow.run(MyAction, params, %{},
  max_retries: 3,
  backoff: 1000  # Initial backoff in milliseconds
)
```

### Async Workflows

For long-running workflows:

```elixir
# Start async workflow
async_ref = Jido.Workflow.run_async(MyAction, params)

# Cancel if needed
Jido.Workflow.cancel(async_ref)

# Wait for result with timeout
case Jido.Workflow.await(async_ref, 5000) do
  {:ok, result} -> handle_success(result)
  {:error, %Error{type: :timeout}} -> handle_timeout()
end
```

### Context Usage

Context can be used to pass cross-cutting concerns:

```elixir
context = %{
  user_id: user.id,
  tenant_id: tenant.id,
  request_id: correlation_id
}

Jido.Workflow.run(MyAction, params, context)
```

This guide covers the core concepts and advanced features of working with Workflows, Actions, Chains, and Closures in Jido. For more detailed information about specific features, consult the hex documentation or the source code.