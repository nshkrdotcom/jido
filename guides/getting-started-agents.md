# Getting Started with Jido Agents

Welcome to the Jido Agents guide! In our previous guide, we explored how Actions serve as composable building blocks for workflows. Now, let's discover how Agents bring these Actions to life by providing a stateful, intelligent wrapper around them.

## What are Agents?

At their core, Jido Agents are simply data structures that understand how to maintain and transform their own state. While you might be familiar with Elixir's built-in Agent processes for state management, Jido Agents take a layered approach. The `Jido.Agent` module provides the foundational data structure, and the `Jido.Agent.Server` provides the GenServer implementation that manages the Agent's runtime state within OTP.

Think of a Jido Agent as a specialized map that knows two important things:
1. What shape its data should have (through its schema)
2. What transformations it can apply to that data (through its registered Actions)

When you create an Agent, you're not starting a process or service - you're creating a data structure that can validate its own contents and understands how to transform itself through Actions. This pure data approach means Agents are predictable, testable, and can be easily serialized or persisted.

### Agents as Data Transformation Engines

The fundamental job of an Agent is to transform data in controlled, predictable ways. It does this through a simple pattern:

1. It holds some initial state (input data)
2. It applies one or more Actions to transform that data
3. It either returns the transformed data or updates its own state

For example, imagine an Agent processing user registration data. It might:
1. Start with raw input: `%{name: "JOHN DOE ", email: "JOHN@EXAMPLE.COM"}`
2. Apply a formatting Action that normalizes the data
3. Store or return the result: `%{name: "John Doe", email: "john@example.com"}`

### The Role of State

An Agent's state is just a schema-validated map. The schema serves several purposes:
- It documents what fields the Agent can contain
- It ensures data consistency through type validation
- It provides default values for fields
- It makes the Agent's purpose clear to other developers

The schema isn't just for validation - it's the Agent's contract with the rest of your system about what data it manages and how that data should look.

#### State Validation Modes

By default, Agents use a permissive validation approach - they validate fields defined in the schema while allowing additional unknown fields. This flexibility supports development workflows and experimental features. For example, you might want to temporarily store debugging information or track experimental metrics without modifying your schema.

However, when you need stricter guarantees about your data, you can enable strict validation mode when setting state. In strict mode, the Agent will reject any fields not defined in its schema. This is valuable when:

- You need to guarantee complete state consistency
- You want to catch typos or mistakes in field names early
- You're working with sensitive data where extra fields could be problematic
- You want to maintain a strict contract about what data an Agent manages

You control this behavior through the `strict_validation` option when setting state, which we'll see in practice shortly.

### Actions and Transformation

While the Agent holds state, Actions do the actual work of transformation. The Agent's job is to:
- Validate that an Action is registered and can be used
- Provide its current state as input to the Action
- Validate and store (or return) the Action's output

Think of it like a pipeline where data flows through one or more transformations, with the Agent ensuring each step maintains data integrity.

### Planning and Execution

One key feature of Agents is their ability to plan sequences of transformations before executing them. When you plan Actions on an Agent, you're creating a queue of transformations to apply. This separation between planning and execution lets you:

1. Validate the entire transformation sequence before running it
2. Ensure Actions will receive the right input at each step
3. Choose whether to apply results to Agent state or just return them
4. Control how results flow between Actions in the sequence

The actual execution happens through a Runner, which orchestrates how the transformations occur and how results flow between steps.

## Creating Your First Agent

Let's create a simple User Registration Agent that will help us understand these concepts. We'll start with the same user registration workflow from our Actions guide, but now we'll wrap it in an Agent:

```elixir
defmodule MyApp.UserAgent do
  use Jido.Agent,
    name: "user_agent",
    description: "Manages user registration",
    # Actions this agent can use
    actions: [FormatUser, EnrichUserData, NotifyUser],
    # State schema
    schema: [
      # Input fields
      name: [
        type: {:or, [:string, nil]}, 
        default: nil,
        doc: "User's raw input name"
      ],
      email: [
        type: {:or, [:string, nil]}, 
        default: nil,
        doc: "User's raw input email"
      ],
      age: [
        type: {:or, [:integer, nil]}, 
        default: nil,
        doc: "User's age in years"
      ],
      
      # Fields that will store action results
      formatted_name: [
        type: {:or, [:string, nil]}, 
        default: nil,
        doc: "Name after formatting"
      ],
      username: [
        type: {:or, [:string, nil]}, 
        default: nil,
        doc: "Generated username"
      ],
      notification_sent: [
        type: :boolean, 
        default: false,
        doc: "Whether welcome notification was sent"
      ]
    ]
end
```

Let's break down this definition:

1. The `name` and `description` help other parts of the system understand what this Agent does
2. The `actions` list declares which Actions this Agent can use
3. The `schema` defines what information this Agent can remember, including both input fields and expected action results

## Working with Agents

Now that we have our Agent defined, let's see how to use it. Working with Agents follows a natural progression of create → set → plan → run.

### Creating an Agent

First, we create a new instance of our Agent:

```elixir
# Create a new agent
agent = MyApp.UserAgent.new()

# It starts with default values
agent.state.name         #=> nil
agent.state.email       #=> nil
agent.state.username    #=> nil

# Each agent has a unique ID
agent.id  #=> "ag_123..."
```

### Setting State

Before we can process anything, we need to give our Agent some data to work with. We can use `set/2` in either permissive or strict mode:

```elixir
# Default permissive mode allows unknown fields
{:ok, agent} = MyApp.UserAgent.set(agent, %{
  name: "John Doe",
  email: "john@example.com",
  debug_info: %{source: "test"}  # Not in schema, but allowed
})

# Strict mode rejects unknown fields
{:error, error} = MyApp.UserAgent.set(agent, 
  %{
    name: "John Doe",
    unknown_field: true
  },
  strict_validation: true
)

# The error clearly identifies rejected fields
assert error.message =~ "Unknown fields: [:unknown_field]"
```

State updates follow these rules:
- Each update returns a new immutable copy of the agent
- Schema fields are always validated
- Unknown fields are allowed by default but can be rejected with strict validation
- Multiple fields can be updated at once
- Existing fields are preserved unless explicitly changed

### Planning Actions

Once our Agent has some state, we can plan what Actions it should take:

```elixir
# Plan a single action using current state
{:ok, agent} = MyApp.UserAgent.plan(agent, FormatUser)

# Plan multiple actions with explicit parameters
{:ok, agent} = MyApp.UserAgent.plan(agent, [
  {FormatUser, agent.state},
  EnrichUserData,
  NotifyUser
])

# Planning doesn't execute - state remains unchanged
assert agent.state.formatted_name == nil
```

The planning phase lets us:
- Validate that all actions are registered
- Set up the transformation sequence
- Prepare parameters for each step
- Check for obvious problems before execution

### Running Actions

Once we've planned our Actions, we can execute them:

```elixir
# Run and apply results to state
{:ok, agent} = MyApp.UserAgent.run(agent, 
  apply_state: true,
  runner: Jido.Runner.Chain
)

# Verify transformations happened
assert agent.state.formatted_name == "John Doe"
assert agent.state.username == "john.doe"
```

Or we can run without updating state to inspect the results first:

```elixir
# Run without applying state changes
{:ok, agent} = MyApp.UserAgent.run(agent, apply_state: false)

# State unchanged but results available
assert agent.state.formatted_name == nil
assert agent.result.result_state.formatted_name == "John Doe"
```

This separation between execution and state updates gives us control over when and how our Agent's state changes.

## Putting It All Together: Commands

While we can use `set`, `plan`, and `run` separately, Jido provides a convenient `cmd/4` function that combines them:

```elixir
{:ok, agent} = MyApp.UserAgent.cmd(
  agent,
  [{FormatUser, agent.state}, EnrichUserData],  # Actions to run
  %{age: 30},                                   # State to set
  apply_state: true,                           # Update state with results
  runner: Jido.Runner.Chain                    # Use chain runner
)

# Everything happened in one step
assert agent.state.formatted_name == "John Doe"
assert agent.state.username == "john.doe"
assert agent.state.age == 30
```

## Best Practices

As you build with Agents, keep these principles in mind:

1. Use strict validation when data consistency is critical and permissive validation during development or for temporary data.

2. Keep your schema focused on the data your Agent truly needs to manage. Just because you can store additional fields doesn't mean you should.

3. Let your Actions handle complex transformations and use `set/2` primarily for direct state updates.

4. Take advantage of the separation between planning and execution to validate operations before running them.

5. Consider whether to apply results to state based on your use case - sometimes you want to inspect results before committing them.

## Next Steps

Now that you understand the basics of Agents, you can explore:
- Complex action chains
- Conditional execution paths
- Error handling and recovery
- State persistence
- Agent supervision and lifecycle
- Inter-agent communication

The test suite provides many examples of these advanced patterns. Remember: Agents are most powerful when they maintain focused state and use well-defined Actions to transform that state. Keep your Agents focused, their state clean, and their Actions clear.