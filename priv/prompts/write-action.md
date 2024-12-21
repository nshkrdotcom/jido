# Writing Jido Actions: A Comprehensive Guide

This guide details how to create robust, well-tested Jido actions that can be composed into larger workflows. Jido actions are discrete, composable units of functionality that follow consistent patterns for validation, execution, and error handling.

## Core Concepts

Jido actions are:
- Self-contained units of work with clearly defined inputs and outputs
- Composable into larger workflows
- Strongly typed with validated parameters
- Fault-tolerant with comprehensive error handling
- Well-documented and tested
- Designed for monitoring and observability

## Action Structure

### Basic Action Template

```elixir
defmodule MyApp.Actions.MyAction do
  @moduledoc """
  Detailed description of what the action does, its purpose,
  and any important considerations for usage.
  """
  
  use Jido.Action,
    name: "my_action",                # Unique identifier for the action
    description: "Action description", # Human-readable description
    category: "category",             # Optional grouping category
    tags: ["tag1", "tag2"],          # Optional tags for filtering
    vsn: "1.0.0",                    # Semantic version
    schema: [                        # Parameter validation schema
      required_param: [
        type: :string,
        required: true,
        doc: "Parameter description"
      ],
      optional_param: [
        type: :integer,
        default: 42,
        doc: "Optional parameter with default"
      ]
    ]

  @impl true
  def run(params, context) do
    with {:ok, validated} <- validate_business_rules(params),
         {:ok, result} <- perform_operation(validated, context) do
      {:ok, %{result: result}}
    end
  end

  # Private implementation functions
  defp validate_business_rules(params) do
    # Business logic validation
  end

  defp perform_operation(params, context) do
    # Core operation logic
  end
end
```

## Parameter Schema Definition

### Available Types

- `:string` - String values
- `:integer` - Integer values
- `:float` - Floating point numbers
- `:boolean` - Boolean values
- `:atom` - Atoms
- `:map` - Map structures
- `:list` - Lists
- `{:list, subtype}` - Lists with specific element types
- `:keyword_list` - Keyword lists
- `{:in, values}` - Enumerated values
- `{:custom, module, function, args}` - Custom validation

### Schema Examples

```elixir
schema: [
  # Required string with documentation
  name: [
    type: :string,
    required: true,
    doc: "User's full name"
  ],
  
  # Integer with range validation
  age: [
    type: :integer,
    required: true,
    doc: "User's age in years",
    validate: &(&1 >= 0 && &1 <= 150)
  ],
  
  # Enumerated values
  status: [
    type: {:in, [:active, :inactive, :pending]},
    default: :pending,
    doc: "Current account status"
  ],
  
  # List with specific type
  tags: [
    type: {:list, :string},
    default: [],
    doc: "Associated tags"
  ],
  
  # Custom validation
  email: [
    type: {:custom, MyApp.Validators, :validate_email, []},
    required: true,
    doc: "Valid email address"
  ]
]
```

## Lifecycle Callbacks

Jido actions support several callbacks for customizing behavior:

### Parameter Validation Callbacks

```elixir
@impl true
def on_before_validate_params(params) do
  # Transform or enhance params before schema validation
  {:ok, params}
end

@impl true
def on_after_validate_params(params) do
  # Transform or enhance params after schema validation
  {:ok, params}
end
```

### Execution Callbacks

```elixir
@impl true
def on_after_run(result) do
  # Transform or enhance the final result
  {:ok, result}
end
```

### Error Handling Callbacks

```elixir
@impl true
def on_error(failed_params, error, context, opts) do
  # Handle or compensate for errors
  {:ok, %{compensated: true, error: error}}
end
```

## Error Handling

### Error Types

- `:validation_error` - Parameter or business rule validation failures
- `:execution_error` - Runtime execution failures
- `:timeout_error` - Operation timeout
- `:compensation_error` - Error during compensation handling
- `:internal_server_error` - Unexpected system errors

### Error Handling Pattern

```elixir
def run(params, context) do
  with {:ok, validated} <- validate_business_rules(params),
       {:ok, external_data} <- fetch_external_data(validated),
       {:ok, processed} <- process_data(external_data),
       {:ok, result} <- format_result(processed) do
    {:ok, result}
  else
    {:error, %Jido.Error{} = error} ->
      {:error, error}
      
    {:error, reason} ->
      {:error, Error.execution_error("Operation failed: #{inspect(reason)}")}
  end
rescue
  e in [RuntimeError, ArgumentError] ->
    {:error, Error.execution_error("Unexpected error: #{Exception.message(e)}")}
end
```

## Testing

### Unit Test Structure

```elixir
defmodule MyApp.Actions.MyActionTest do
  use ExUnit.Case, async: true
  
  alias MyApp.Actions.MyAction
  
  describe "run/2" do
    test "successfully processes valid input" do
      params = %{required_param: "value"}
      context = %{user_id: "123"}
      
      assert {:ok, result} = MyAction.run(params, context)
      assert result.processed == "value"
    end
    
    test "handles invalid parameters" do
      params = %{invalid: "params"}
      
      assert {:error, %Jido.Error{type: :validation_error}} =
        MyAction.run(params, %{})
    end
    
    test "handles external service failures" do
      params = %{trigger_error: true}
      
      assert {:error, %Jido.Error{type: :execution_error}} =
        MyAction.run(params, %{})
    end
  end
  
  describe "parameter validation" do
    test "validates required parameters" do
      assert {:error, %Jido.Error{type: :validation_error}} =
        MyAction.validate_params(%{})
    end
    
    test "applies default values" do
      assert {:ok, validated} =
        MyAction.validate_params(%{required_param: "value"})
      assert validated.optional_param == 42
    end
  end
end
```

### Testing Callbacks

```elixir
describe "lifecycle callbacks" do
  test "transforms parameters before validation" do
    params = %{input: "raw"}
    assert {:ok, transformed} = MyAction.on_before_validate_params(params)
    assert transformed.input == "processed"
  end
  
  test "enhances result after execution" do
    result = %{value: 42}
    assert {:ok, enhanced} = MyAction.on_after_run(result)
    assert enhanced.timestamp != nil
  end
end
```

## Best Practices

### Action Design

1. **Single Responsibility**
   - Each action should do one thing well
   - Break complex operations into multiple actions
   - Use action chains for complex workflows

2. **Input Validation**
   - Validate all input parameters
   - Use schema validation for type checking
   - Add business rule validation
   - Handle edge cases explicitly

3. **Error Handling**
   - Return tagged tuples consistently
   - Use appropriate error types
   - Include meaningful error messages
   - Implement compensation when needed

4. **Security**
   - Validate and sanitize all inputs
   - Handle credentials securely
   - Log sensitive data appropriately
   - Consider rate limiting for external services

5. **Documentation**
   - Add clear @moduledoc and @doc
   - Document all parameters
   - Include usage examples
   - Note any side effects

6. **Testing**
   - Test happy path thoroughly
   - Test all error cases
   - Test parameter validation
   - Test lifecycle callbacks
   - Use property-based testing for complex inputs

### Logging and Monitoring

```elixir
def run(params, context) do
  Logger.info("Starting action", %{
    action: __MODULE__,
    params: redact_sensitive(params),
    context: context
  })
  
  # ... action logic ...
  
  Logger.info("Action completed", %{
    action: __MODULE__,
    duration_ms: duration,
    result: redact_sensitive(result)
  })
end

defp redact_sensitive(data) do
  # Implement appropriate data redaction
end
```

## Advanced Features

### Compensation

```elixir
use Jido.Action,
  name: "compensating_action",
  compensation: [
    enabled: true,
    max_retries: 3,
    timeout: 5000
  ]

def on_error(failed_params, error, context, _opts) do
  # Implement compensation logic
  {:ok, %{compensated: true, error: error}}
end
```

### Rate Limiting

```elixir
use Jido.Action,
  name: "rate_limited_action"

@max_requests 100
@window_ms 60_000

def run(params, context) do
  with :ok <- check_rate_limit(),
       {:ok, result} <- process_request(params) do
    {:ok, result}
  end
end

defp check_rate_limit do
  # Implement rate limiting logic
end
```

### Async Operations

```elixir
def run(params, context) do
  task = Task.async(fn ->
    # Long-running operation
  end)
  
  case Task.yield(task, :timer.seconds(30)) do
    {:ok, result} -> {:ok, result}
    nil ->
      Task.shutdown(task)
      {:error, Error.timeout("Operation timed out")}
  end
end
```

## Common Pitfalls

1. **Overly Complex Actions**
   - Break down complex actions into smaller, focused ones
   - Use action chains for orchestration
   - Keep the single responsibility principle in mind

2. **Inadequate Error Handling**
   - Always return tagged tuples
   - Handle all error cases explicitly
   - Provide meaningful error messages
   - Consider retry strategies

3. **Missing Validation**
   - Validate all inputs thoroughly
   - Include business rule validation
   - Handle edge cases explicitly
   - Consider security implications

4. **Poor Testing**
   - Test all code paths
   - Include error cases
   - Test with various inputs
   - Test lifecycle callbacks

5. **Insufficient Documentation**
   - Document purpose and usage
   - Include parameter descriptions
   - Note side effects
   - Provide examples

## Example Actions

### Simple Action

```elixir
defmodule MyApp.Actions.FormatName do
  use Jido.Action,
    name: "format_name",
    description: "Formats a name into a consistent format",
    schema: [
      first_name: [type: :string, required: true],
      last_name: [type: :string, required: true]
    ]

  def run(%{first_name: first, last_name: last}, _context) do
    formatted = String.trim("#{capitalize(first)} #{capitalize(last)}")
    {:ok, %{formatted_name: formatted}}
  end
  
  defp capitalize(str) do
    str
    |> String.trim()
    |> String.capitalize()
  end
end
```

### Complex Action

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action,
    name: "process_order",
    description: "Processes a new order with validation and compensation",
    compensation: [enabled: true],
    schema: [
      order_id: [type: :string, required: true],
      items: [type: {:list, :map}, required: true],
      user_id: [type: :string, required: true]
    ]

  def run(params, context) do
    with {:ok, validated} <- validate_order(params),
         {:ok, inventory} <- check_inventory(validated.items),
         {:ok, payment} <- process_payment(validated, context),
         {:ok, order} <- create_order(validated, payment) do
      {:ok, %{order_id: order.id, status: :completed}}
    end
  end
  
  def on_error(params, error, _context, _opts) do
    # Implement compensation logic
    {:ok, %{compensated: true, error: error}}
  end
  
  defp validate_order(params) do
    # Implement order validation
  end
  
  defp check_inventory(items) do
    # Implement inventory check
  end
  
  defp process_payment(order, context) do
    # Implement payment processing
  end
  
  defp create_order(params, payment) do
    # Implement order creation
  end
end
```

Remember that these examples and guidelines should be adapted to your specific use case and requirements. The key is to maintain consistency, reliability, and maintainability in your action implementations.