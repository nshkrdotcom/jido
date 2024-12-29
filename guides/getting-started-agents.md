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

### Why allow unknown state fields?

Only known fields are validated against the schema. If you want to store data that isn't part of the Agent's schema, you can do so by adding it to the Agent's state. This is useful in a few cases:

1. When you want to store results from an Action that isn't known to the Agent. For example, you may want to store the result of an Action in a field that isn't part of the Agent's schema.
2. When you want to store data that will be used by an Action, but isn't part of the Agent's schema. For example, you may want to store the result of an Action in a field that isn't part of the Agent's schema.
3. This makes the development experience easier and more flexible.

Given that Actions also validate their inputs, this allows us to be more flexible in how tightly we enforce schema validation at the Agent level.

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

This structured approach to data transformation makes Agents particularly good at:
- Maintaining complex state that changes in well-defined ways
- Orchestrating multi-step data processing workflows
- Ensuring data consistency through schema validation
- Making state changes traceable and predictable

As we continue through this guide, we'll see how these concepts come together in practical examples. Remember: an Agent is just a smart data structure that knows how to transform itself in controlled ways through Actions.

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

1. The `name` and `description` help other parts of the system understand what this Agent does via Agent Discovery.

2. The `actions` list declares which Actions this Agent can use - like listing the tools in its toolbelt

3. The `schema` defines what information this Agent can remember:
   - Input fields store raw data we receive
   - Result fields store outputs from our Actions
   - Types and defaults ensure our state stays valid

This schema-based approach gives us several benefits:
- Type safety (can't store invalid data for known fields)
- Documentation (fields are self-describing)
- Default values (fields start empty)
- Clarity about what the Agent manages

## Working with Agents

Now that we have our Agent defined, let's see how to use it. Working with Agents follows a natural progression:

1. Create an Agent instance
2. Set some state
3. Plan what Actions to take
4. Execute those Actions

Let's walk through each step.

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

The new Agent starts with empty state but knows about:
- Its schema (what data it can hold)
- Its available Actions (what it can do)
- Its identity (unique ID)

### Setting State

Before we can process anything, we need to give our Agent some data to work with. We do this with `set/2`:

```elixir
# Set a single field
{:ok, agent} = MyApp.UserAgent.set(agent, name: "John Doe")

# Set multiple fields at once
{:ok, agent} = MyApp.UserAgent.set(agent, %{
  name: "John Doe ",          # Note trailing space
  email: "JOHN@EXAMPLE.COM",  # Will be normalized
  age: 30
})

# The schema ensures data validity
MyApp.UserAgent.set(agent, age: "thirty")  
#=> {:error, %Jido.Error{type: :validation_error, message: "age must be an integer"}}
```

Some important things to notice:
- State updates return `{:ok, agent}` on success
- The agent is immutable - each update returns a new copy
- Schema validation happens automatically
- We can update one or many fields at once

### Planning Actions with Instructions

#### Instructions vs. Actions

Actions are the building blocks of Jido workflows. When we want to apply an Action to an Agent, we describe that as an "Instruction". Instructions are the data structure that describes what Action to apply and what state to pass to it.

- Instructions may be an Action module
- Instructions may be a tuple of an Action module and a state map
- Instructions may be a list of action modules or action tuples

```elixir
# An action module
instructions = FormatUser

# A tuple of an action module and a state map
instructions = {FormatUser, agent.state}

# A list of action modules or action tuples
instructions = [FormatUser, {EnrichUserData, %{age: 30}}, NotifyUser]
```

#### Planning

Once our Agent has some state, we can plan what Actions it should take. Planning is like creating a to-do list for the Agent:

```elixir
# Plan a single instruction
{:ok, agent} = MyApp.UserAgent.plan(agent, FormatUser)

# Plan a sequence of instructions
{:ok, agent} = MyApp.UserAgent.plan(agent, [
  {FormatUser, agent.state},    # Pass current state as parameters
  EnrichUserData,                
  NotifyUser                    
])

# Important: Planning doesn't execute anything yet!
agent.state.formatted_name  #=> nil
```

Some key points about planning:
- Instructions do not assume any input state - they are just the actions and their parameters
- It's just creating a queue of work to do
- No state changes happen during planning other than setting the instructions
- You can plan multiple actions in sequence
- The agent validates that it knows each Action

### Running Instructions

Once we've planned our Instructions, we can execute them:

```elixir
# Run with state updates
{:ok, agent} = MyApp.UserAgent.run(agent, 
  apply_state: true,    # Update agent state with results
  runner: Jido.Runner.Chain  # Use chain runner for sequences, Simple runner only executes the next instruction
)

# Now we can see the results
agent.state.formatted_name  #=> "John Doe"     # Spaces trimmed
agent.state.username       #=> "john.doe"     # Generated
agent.state.notification_sent  #=> true       # Email sent
```

The `run/2` function provides options for controlling execution:
- `apply_state: boolean()` - Should results update agent state?
- `runner: module()` - Which runner to use (Simple or Chain)

### Examining Results

Agents maintain both state and result history:

```elixir
# Run without applying state
{:ok, agent} = MyApp.UserAgent.run(agent, apply_state: false)

# State stays unchanged
agent.state.formatted_name  #=> nil

# But results are available
agent.result.status         #=> :ok
agent.result.result_state   #=> %{formatted_name: "John Doe", ...}
agent.result.initial_state  #=> (original state before run)
```

This separation between state and results lets us:
- Inspect what changed
- Decide whether to keep changes
- Track the history of operations

## Putting It All Together: The Command Pattern

While we can use `set`, `plan`, and `run` separately, Jido provides a convenient `cmd/4` function that combines them:

```elixir
# Combine set, plan, and run in one operation
{:ok, agent} = MyApp.UserAgent.cmd(
  agent,
  [{FormatUser, agent.state}, EnrichUserData],  # Actions to run
  %{age: 30},                                   # State to set
  apply_state: true,                           # Update state with results
  runner: Jido.Runner.Chain                    # Use chain runner
)

# Everything happened in one step
agent.state.age            #=> 30
agent.state.formatted_name #=> "John Doe"
agent.state.username      #=> "john.doe"
```

This pattern is useful when you want to:
- Update state and run actions atomically
- Keep your code more concise
- Ensure operations happen in sequence

## Best Practices

As you build with Agents, keep these principles in mind:

1. **Clear State Boundaries**: Your schema should clearly show what data the Agent manages. Don't store everything just because you can.

2. **Action Registration**: Register only the Actions this Agent actually needs. This makes the Agent's capabilities clear and prevents misuse.

3. **State Updates**: Use `set/2` for direct state updates and let Actions handle complex transformations.

4. **Planning vs Running**: Take advantage of the separation between planning and execution. It lets you validate operations before running them.

5. **Result Handling**: Consider whether to apply results to state based on your use case. Sometimes you want to inspect results before committing them.

## Next Steps

Now that you understand the basics of Agents, you can explore:
- Complex action chains
- Conditional execution paths
- Error handling and recovery
- State persistence
- Agent supervision and lifecycle
- Inter-agent communication

The test suite provides many examples of these advanced patterns.

Remember: Agents are most powerful when they maintain focused state and use well-defined Actions to transform that state. Keep your Agents focused, their state clean, and their Actions clear.