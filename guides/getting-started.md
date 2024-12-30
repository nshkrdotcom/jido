# Getting Started with Jido

Welcome to **Jido** (自動), a powerful yet approachable Elixir framework for building autonomous, distributed agent systems. Whether you're building complex business processes, service orchestration, or adaptive workflows, Jido provides a robust foundation for your autonomous agents.

## Overview

Jido is built around four core concepts that work together to create intelligent, adaptable systems:

1. **Actions**: Discrete, reusable units of work
2. **Workflows**: Sequences of Actions that accomplish larger goals
3. **Agents**: Stateful entities that can plan and execute workflows
4. **Sensors**: Real-time monitoring and data gathering components

Let's see how these pieces fit together.

## Installation

Add Jido to your project's dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 1.0.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start Example

Here's a complete example showing all major components working together in a user registration system:

```elixir
# 1. Define an Action
defmodule MyApp.Actions.FormatUser do
  use Jido.Action,
    name: "format_user",
    description: "Formats user data",
    schema: [
      name: [type: :string, required: true],
      email: [type: :string, required: true]
    ]

  def run(params, _context) do
    {:ok, %{
      formatted_name: String.trim(params.name),
      email: String.downcase(params.email)
    }}
  end
end

# 2. Create a Sensor to monitor registrations
defmodule MyApp.Sensors.RegistrationCounter do
  use Jido.Sensor,
    name: "registration_counter",
    description: "Tracks registration metrics",
    schema: [
      emit_interval: [type: :pos_integer, default: 1000]
    ]

  def mount(opts) do
    {:ok, Map.merge(opts, %{successful: 0, failed: 0})}
  end

  def handle_info({:registration, :success}, state) do
    new_state = %{state | successful: state.successful + 1}
    {:noreply, new_state}
  end
end

# 3. Define an Agent to manage registrations
defmodule MyApp.Agents.RegistrationAgent do
  use Jido.Agent,
    name: "registration_agent",
    description: "Manages user registration process",
    actions: [MyApp.Actions.FormatUser],
    schema: [
      registrations: [type: :integer, default: 0],
      last_registration: [type: {:or, [:map, nil]}, default: nil]
    ]

  def on_after_run(agent, result) do
    new_count = agent.state.registrations + 1
    {:ok, %{agent | state: %{agent.state | 
      registrations: new_count,
      last_registration: result
    }}}
  end
end

# 4. Use it all together
defmodule MyApp.Example do
  def register_user do
    # Create and configure the agent
    agent = MyApp.Agents.RegistrationAgent.new()
    
    # Execute a registration
    {:ok, agent} = MyApp.Agents.RegistrationAgent.cmd(
      agent,
      MyApp.Actions.FormatUser,
      %{
        name: "John Doe ",
        email: "JOHN@EXAMPLE.COM"
      }
    )

    # Results are stored in agent state
    agent.state.last_registration
  end
end
```

## Key Concepts Explained

### Actions: The Building Blocks

Actions are small, focused pieces of functionality that:
- Have a clear input schema
- Perform one specific task
- Return standardized results
- Can be composed into workflows

[Learn more about Actions →](guides/actions.md)

### Workflows: Combining Actions

Workflows chain Actions together to accomplish larger goals:
- Pass data between Actions automatically
- Handle errors consistently
- Support async execution
- Enable conditional paths

Example workflow:
```elixir
alias MyApp.Actions.{FormatUser, EnrichData, NotifyUser}

{:ok, result} = Jido.Workflow.Chain.chain(
  [FormatUser, EnrichData, NotifyUser],
  %{name: "John Doe", email: "john@example.com"}
)
```

### Agents: Stateful Intelligence

Agents provide stateful wrappers around Actions with:
- Schema-validated state management
- Action planning and execution
- Runtime adaptation through directives
- Lifecycle callbacks

[Learn more about Agents →](guides/agents.md)

### Sensors: Real-time Monitoring

Sensors gather data and monitor system state:
- Run as independent processes
- Emit standardized signals
- Support real-time metrics
- Enable adaptive behavior

[Learn more about Sensors →](guides/sensors.md)

## Running in Production

To run Jido in production, start your components under supervision:

```elixir
# In your application.ex
children = [
  {Registry, keys: :unique, name: Jido.AgentRegistry},
  {Phoenix.PubSub, name: MyApp.PubSub},
  {Jido.Agent.Supervisor, pubsub: MyApp.PubSub},
  
  # Start your agent server
  {Jido.Agent.Server, 
    agent: MyApp.Agents.RegistrationAgent.new(),
    name: "registration_1"
  },
  
  # Start your sensor
  {MyApp.Sensors.RegistrationCounter,
    name: "counter_1",
    pubsub: MyApp.PubSub,
    topic: "registration_metrics"
  }
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Next Steps

Now that you understand the basics, you can explore:

1. [Building Complex Actions and Workflows](guides/actions.md)
   - Action composition patterns
   - Error handling
   - Async execution
   - Testing strategies

2. [Creating Smart Agents](guides/agents.md)
   - State management
   - Planning and execution
   - Lifecycle hooks
   - Directive system

3. [Implementing Sensors](guides/sensors.md)
   - Signal design
   - Real-time monitoring
   - Metric collection
   - Event processing

4. [Using Agent Directives](guides/agent-directives.md)
   - Runtime adaptation
   - Dynamic capabilities
   - Self-modification patterns

## Additional Resources

- [Complete Documentation](https://hexdocs.pm/jido)
- [GitHub Repository](https://github.com/agentjido/jido)
- [Examples and Tutorials](guides/)

For AI/LLM integration capabilities, see the separate [`jido_ai`](https://github.com/agentjido/jido_ai) package.

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for guidelines.

## License

Apache License 2.0 - See [LICENSE.md](LICENSE.md) for details.