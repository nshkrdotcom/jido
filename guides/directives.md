# Agent Directives

In our previous guides, we explored how Agents provide stateful wrappers around Actions and how Signals enable real-time monitoring. Now, let's discover how Directives enable agents to modify their own behavior and capabilities at runtime.

## Understanding Directives

Directives are special instructions that allow agents to modify their own state and capabilities. Think of them as meta-actions that let agents:

1. Queue up new actions to execute (Enqueue)
2. Learn new capabilities (RegisterAction) 
3. Remove capabilities (DeregisterAction)

This self-modification ability is crucial for building adaptive agents that can:
- Respond to new situations by queueing appropriate actions
- Learn new behaviors by registering actions
- Optimize themselves by removing unused capabilities
- Build complex workflows dynamically

Let's see how to implement these patterns.

## Creating Your First Directive-Based Agent

We'll create an agent that can adapt its behavior by learning new arithmetic operations. This will demonstrate how directives enable runtime evolution of agent capabilities.

```elixir
defmodule MyApp.AdaptiveCalculator do
  use Jido.Agent,
    name: "adaptive_calculator",
    description: "A calculator that can learn new operations",
    actions: [
      # Core actions for self-modification
      Jido.Actions.Directives.EnqueueAction,
      Jido.Actions.Directives.RegisterAction,
      Jido.Actions.Directives.DeregisterAction,
      
      # Initial arithmetic capabilities
      MyApp.Actions.Add,
      MyApp.Actions.Subtract
    ],
    schema: [
      value: [type: :float, default: 0.0],
      operations_used: [type: {:list, :atom}, default: []],
      last_operation: [type: {:or, [:atom, nil]}, default: nil]
    ]

  # Optional callbacks for tracking operations
  def on_after_run(agent, result) do
    case result do
      %{status: :ok, action: action} ->
        operations = [action | agent.state.operations_used] |> Enum.uniq()
        {:ok, %{agent | state: Map.put(agent.state, :operations_used, operations)}}
      _ ->
        {:ok, agent}
    end
  end
end
```

Now let's implement some basic arithmetic actions that can work with our calculator:

```elixir
defmodule MyApp.Actions.Add do
  use Jido.Action,
    name: "add",
    description: "Adds a number to the current value",
    schema: [
      value: [type: :float, required: true],
      amount: [type: :float, required: true]
    ]

  def run(%{value: current, amount: amount}, _context) do
    {:ok, %{value: current + amount}}
  end
end

defmodule MyApp.Actions.Multiply do
  use Jido.Action,
    name: "multiply",
    description: "Multiplies the current value by an amount",
    schema: [
      value: [type: :float, required: true],
      amount: [type: :float, required: true]
    ]

  def run(%{value: current, amount: amount}, _context) do
    {:ok, %{value: current * amount}}
  end
end

defmodule MyApp.Actions.Power do
  use Jido.Action,
    name: "power",
    description: "Raises the current value to a power",
    schema: [
      value: [type: :float, required: true],
      exponent: [type: :float, required: true]
    ]

  def run(%{value: current, exponent: exp}, _context) do
    {:ok, %{value: :math.pow(current, exp)}}
  end
end
```

## Working with Directives

Let's explore how our calculator can use directives to evolve its capabilities:

### 1. Queueing New Operations (Enqueue)

The Enqueue lets an agent add new instructions to its pending queue. This is useful for building dynamic workflows:

```elixir
# Create our calculator
calculator = MyApp.AdaptiveCalculator.new()

# Start with a simple addition
{:ok, calculator} = MyApp.AdaptiveCalculator.set(calculator, %{value: 5})

# Queue up a sequence of operations using EnqueueAction
{:ok, calculator} = MyApp.AdaptiveCalculator.cmd(
  calculator,
  [
    # Utilize a directive to queue up an instruction rather than planning it directly
    {Jido.Actions.Directives.EnqueueAction, %{
      action: MyApp.Actions.Add,
      params: %{amount: 10}
    }},
    {Jido.Actions.Directives.EnqueueAction, %{
      action: MyApp.Actions.Add,
      params: %{amount: 20}
    }}
  ]
)

# Final value should be 35 (5 + 10 + 20)
calculator.state.value #=> 35.0
```

### 2. Learning New Operations (RegisterAction)

The RegisterAction lets an agent learn new capabilities at runtime:

```elixir
# Our calculator doesn't know how to multiply yet
{:error, _} = MyApp.AdaptiveCalculator.plan(calculator, MyApp.Actions.Multiply)

# Teach it multiplication
{:ok, calculator} = MyApp.AdaptiveCalculator.cmd(
  calculator,
  {Jido.Actions.Directives.RegisterAction, %{
    action_module: MyApp.Actions.Multiply
  }}
)

# Now we can multiply!
{:ok, calculator} = MyApp.AdaptiveCalculator.cmd(
  calculator,
  {MyApp.Actions.Multiply, %{amount: 2}}
)

calculator.state.value #=> 70.0  # (35 * 2)
```

### 3. Removing Operations (DeregisterAction)

The DeregisterAction lets an agent remove capabilities it no longer needs:

```elixir
# Remove multiplication if we don't need it anymore
{:ok, calculator} = MyApp.AdaptiveCalculator.cmd(
  calculator,
  {Jido.Actions.Directives.DeregisterAction, %{
    action_module: MyApp.Actions.Multiply
  }}
)

# Trying to multiply now will fail
{:error, _} = MyApp.AdaptiveCalculator.plan(calculator, MyApp.Actions.Multiply)
```

## Building Complex Self-Modifying Workflows

Directives become really powerful when combined into workflows that let agents adapt their behavior based on conditions. Here's an example of a calculator that learns more advanced operations when needed:

```elixir
defmodule MyApp.Actions.LearnAdvancedMath do
  use Jido.Action,
    name: "learn_advanced_math",
    description: "Teaches the calculator advanced operations",
    schema: [
      value: [type: :float, required: true]
    ]

  def run(%{value: value}, _context) do
    # First register the power operation
    power_directive = %Jido.Agent.Directive.RegisterAction{
      action_module: MyApp.Actions.Power
    }

    # Then queue up a calculation using it
    calculate_directive = %Jido.Agent.Directive.Enqueue{
      action: MyApp.Actions.Power,
      params: %{value: value, exponent: 2}
    }

    # Return both directives to be applied in order
    {:ok, [power_directive, calculate_directive]}
  end
end

# Use our advanced learning action
calculator = MyApp.AdaptiveCalculator.new()
{:ok, calculator} = MyApp.AdaptiveCalculator.set(calculator, %{value: 5})

# Learn and apply advanced math
{:ok, calculator} = MyApp.AdaptiveCalculator.cmd(
  calculator,
  [
    {MyApp.Actions.LearnAdvancedMath, %{}},  # This will register Power and queue its use
    {Jido.Actions.Directives.EnqueueAction, %{  # Then we'll queue another operation
      action: MyApp.Actions.Add,
      params: %{amount: 10}
    }}
  ]
)

# Final value: 5^2 + 10 = 35
calculator.state.value #=> 35.0
```

## Best Practices

When working with directives, keep these principles in mind:

1. **Capability Management**
   - Only register actions the agent actually needs
   - Consider deregistering unused actions to keep the agent focused
   - Track which operations are most frequently used

2. **Directive Chains**
   - Order directives carefully - registration must happen before usage
   - Consider using composite actions for complex directive sequences
   - Validate directive success before proceeding

3. **State Evolution**
   - Keep track of how agent capabilities change over time
   - Consider implementing rollback mechanisms for failed directive chains
   - Use callbacks to monitor and log capability changes

4. **Testing**
   - Test both successful and failed directive applications
   - Verify capability addition and removal
   - Test complex directive chains
   - Check state consistency after directive application

## Next Steps

Now that you understand directives, you can explore:
- More complex self-modification patterns
- Conditional capability loading
- Dynamic workflow construction
- State-based capability management
- Multi-agent capability sharing

Remember: Directives give agents the power to evolve and adapt. Use them thoughtfully to create agents that can grow and optimize themselves while maintaining stability and predictability.