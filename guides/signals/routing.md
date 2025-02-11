# Signal Routing in Jido

Signal routing in Jido enables sophisticated message handling patterns across your agent system. This guide explores Jido's trie-based routing system, from basic path patterns to advanced configuration.

## Overview

The routing system determines how signals flow through your agent network by matching signal types against predefined patterns. It supports:

- Path-based routing with dot notation
- Wildcard pattern matching
- Priority-based handler execution
- Pattern matching functions
- Dynamic route management

## Core Concepts

### Path Patterns

Signal routes use a dot-notation syntax that supports three types of matching:

1. **Exact Matches**: Match specific segments

   ```elixir
   "user.created"  # Matches exactly "user.created"
   ```

2. **Single Wildcards**: Match any single segment

   ```elixir
   "user.*.updated"  # Matches "user.123.updated", "user.abc.updated", etc.
   ```

3. **Multi-level Wildcards**: Match zero or more segments
   ```elixir
   "audit.**"  # Matches "audit.user", "audit.payment.processed", etc.
   ```

### Handler Priority

Handlers execute in order based on:

1. Path complexity (more specific paths execute first)
2. Explicit priority (-100 to 100, higher executes first)
3. Registration order (for equal priority/complexity)

## Basic Usage

### Creating a Router

```elixir
{:ok, router} = Router.new([
  # Simple route with default priority
  {"user.created", %Instruction{action: HandleUserCreated}},

  # High-priority audit logging
  {"audit.**", %Instruction{action: AuditLogger}, 100},

  # Pattern matching for specific conditions
  {"payment.processed",
    fn signal -> signal.data.amount > 1000 end,
    %Instruction{action: HandleLargePayment}}
])
```

### Routing Signals

```elixir
# Create a signal
signal = %Signal{
  type: "payment.processed",
  data: %{amount: 2000}
}

# Route the signal
{:ok, instructions} = Router.route(router, signal)
```

## Path Pattern Rules

Paths must follow these rules:

1. Match the pattern: `^[a-zA-Z0-9.*_-]+(\.[a-zA-Z0-9.*_-]+)*$`
2. Cannot contain consecutive dots (..)
3. Cannot contain consecutive multi-wildcards (`**...**`)

Examples:

```elixir
# Valid patterns
"user.created"
"user.*.updated"
"audit.**"
"user.*.profile.**"

# Invalid patterns
"user..created"      # Consecutive dots
"user.**.**"        # Consecutive multi-wildcards
"user@123"          # Invalid characters
```

## Multiple Instruction Matching

One of Jido's powerful features is the ability to match multiple instructions for a single signal type. When multiple handlers match a signal, they are executed in a well-defined order based on path complexity, priority, and registration sequence.

### Instruction Ordering

Instructions are ordered according to these rules:

1. Path Complexity (highest to lowest)

   - More specific paths execute before wildcards
   - Exact matches have highest precedence
   - Single wildcards (\*) have medium precedence
   - Multi-level wildcards (\*\*) have lowest precedence

2. Priority (-100 to 100, highest first)

   - Higher priority handlers execute first
   - Equal priority maintains registration order

3. Registration Order
   - For equal complexity and priority, earlier registrations execute first

```elixir
# Multiple handlers for the same path
Router.new([
  # Executes first (highest priority)
  {"user.created", %Instruction{action: AuditNewUser}, 100},

  # Executes second (default priority)
  {"user.created", %Instruction{action: CreateUserProfile}},

  # Executes third (lowest priority)
  {"user.created", %Instruction{action: NotifyAdmins}, -50}
])

# Complex pattern matching
Router.new([
  # Executes first (exact match)
  {"user.123.profile.updated", %Instruction{action: HandleSpecificUser}},

  # Executes second (single wildcard)
  {"user.*.profile.updated", %Instruction{action: HandleAnyUserProfile}},

  # Executes third (multi-wildcard)
  {"user.**", %Instruction{action: LogUserEvents}}
])
```

### PID Delegation

Routes can be delegated directly to PIDs, enabling parent agents to route signals to their children or to other specific processes. This is particularly useful in hierarchical agent architectures.

```elixir
# Create a child process
child_pid = spawn_link(fn ->
  receive do
    {:signal, signal} -> handle_signal(signal)
  end
end)

# Route signals to the child
Router.new([
  # Direct PID delegation
  {"child.events", child_pid},

  # Mixed routing - some to PID, some to handlers
  {"child.*.important", %Instruction{action: ParentHandler}},
  {"child.*", child_pid}
])
```

PID delegation features:

1. **Automatic Signal Wrapping**: Signals are automatically wrapped in a `{:signal, signal}` tuple
2. **Process Monitoring**: Routes are validated against living processes
3. **Async Communication**: Messages are sent asynchronously by default
4. **Error Handling**: Graceful handling of dead process references

Example with multiple children:

```elixir
defmodule ParentAgent do
  use Jido.Agent

  def init(children) do
    routes = Enum.map(children, fn {type, pid} ->
      # Each child handles its own type of signals
      {"#{type}.**", pid}
    end)

    {:ok, router} = Router.new(routes)
    {:ok, %{router: router, children: children}}
  end
end

# Usage
children = [
  {"orders", spawn_link(OrderProcessor)},
  {"users", spawn_link(UserManager)},
  {"payments", spawn_link(PaymentHandler)}
]
ParentAgent.start_link(children)
```

## Advanced Features

### Pattern Matching Functions

Use pattern matching functions for complex routing logic:

```elixir
Router.new([
  {"payment.processed",
    fn signal ->
      # Match payments over $1000 in USD
      signal.data.amount > 1000 && signal.data.currency == "USD"
    end,
    %Instruction{action: HandleLargeUSDPayment}
  }
])
```

### Priority Management

```elixir
Router.new([
  # High priority (75-100): Critical system handlers
  {"system.error", %Instruction{action: ErrorHandler}, 100},

  # Medium priority (0-74): Business logic
  {"user.created", %Instruction{action: CreateUser}, 50},

  # Low priority (-100 to -1): Logging, metrics
  {"**.processed", %Instruction{action: MetricsCollector}, -50}
])
```

### Dynamic Route Management

Add or remove routes at runtime:

```elixir
# Add new routes
{:ok, router} = Router.add(router, [
  {"metrics.**", %Instruction{action: CollectMetrics}}
])

# Remove routes
{:ok, router} = Router.remove(router, "metrics.**")
```

### Router Merging

Combine routes from multiple routers:

```elixir
{:ok, router1} = Router.new([{"user.created", user_handler}])
{:ok, router2} = Router.new([{"payment.processed", payment_handler}])

# Merge router2's routes into router1
{:ok, merged} = Router.merge(router1, router2)
```

## Best Practices

### Route Design

1. Use consistent, hierarchical path patterns

   ```elixir
   # Good
   "user.profile.updated"
   "user.settings.changed"

   # Avoid
   "updateUserProfile"
   "change-settings-user"
   ```

2. Prefer specific routes over wildcards when possible

   ```elixir
   # Better
   "user.profile.updated"

   # More general
   "user.*.updated"
   ```

3. Document your path hierarchy
   ```elixir
   # Example path structure
   "domain.entity.action[.qualifier]"
   # e.g., "user.profile.updated.success"
   ```

### Priority Management

1. Reserve high priorities (75-100) for critical handlers
2. Use default priority (0) for standard business logic
3. Use low priorities (-100 to -75) for metrics/logging
4. Document priority ranges for your application

### Pattern Matching

1. Keep match functions simple and fast
2. Handle nil/missing data gracefully
3. Avoid side effects in match functions
4. Test edge cases thoroughly

### Performance Optimization

1. Monitor route count in production
2. Use pattern matching sparingly
3. Consider complexity scores when designing paths
4. Profile routing performance under load

## Error Handling

The router provides detailed errors for common issues:

```elixir
# Invalid path pattern
{:error, %Error{type: :routing_error, message: "Path cannot contain consecutive dots"}}

# Priority out of bounds
{:error, %Error{type: :routing_error, message: "Priority value exceeds maximum allowed"}}

# No matching handlers
{:error, %Error{type: :routing_error, message: "No matching handlers found for signal"}}
```

## Advanced Pattern Examples

### Complex Wildcard Interactions

```elixir
Router.new([
  # Catch-all with lowest priority
  {"**", %Instruction{action: CatchAll}, -100},

  # More specific patterns take precedence
  {"*.*.created", %Instruction{action: HandleCreation}},
  {"user.**", %Instruction{action: HandleUserEvents}},
  {"user.*.created", %Instruction{action: HandleUserCreation}},
  {"user.123.created", %Instruction{action: HandleSpecificUser}}
])
```

### State-Based Routing

```elixir
Router.new([
  {"order.status.changed",
    fn signal ->
      # Route based on order state transition
      old_status = signal.data.old_status
      new_status = signal.data.new_status
      old_status == "pending" && new_status == "processing"
    end,
    %Instruction{action: HandleOrderProcessing}}
])
```

## Implementation Details

The router uses several specialized structs:

- `Route` - Defines a single routing rule
- `TrieNode` - Internal trie structure node
- `HandlerInfo` - Stores handler metadata
- `PatternMatch` - Encapsulates pattern matching rules

The trie structure enables efficient path matching while maintaining proper execution order based on complexity and priority.

## Testing Strategies

1. Test exact matches

   ```elixir
   test "routes exact path signal" do
     {:ok, router} = Router.new({"user.created", handler})
     signal = %Signal{type: "user.created"}
     assert {:ok, [^handler]} = Router.route(router, signal)
   end
   ```

2. Test wildcard patterns

   ```elixir
   test "routes wildcard signal" do
     {:ok, router} = Router.new({"user.*.updated", handler})
     signal = %Signal{type: "user.123.updated"}
     assert {:ok, [^handler]} = Router.route(router, signal)
   end
   ```

3. Test priority ordering
   ```elixir
   test "executes handlers in priority order" do
     {:ok, router} = Router.new([
       {"test", handler1, 100},
       {"test", handler2, 0}
     ])
     signal = %Signal{type: "test"}
     assert {:ok, [^handler1, ^handler2]} = Router.route(router, signal)
   end
   ```

## See Also

- `Jido.Signal` - Signal structure and validation
- `Jido.Instruction` - Handler instruction format
- `Jido.Error` - Error types and handling
