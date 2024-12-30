# Jido (自動)

The name "Jido" (自動) comes from the Japanese word meaning "automatic" or "automated", where 自 (ji) means "self" and 動 (dō) means "movement".

Jido is a foundational framework for building autonomous, distributed agent systems in Elixir.

> **Note**: Jido is a foundational framework that does not include AI or LLM capabilities out of the box. For AI integration, please see the separate [`jido_ai`](https://github.com/agentjido/jido_ai) package which provides custom actions for AI/LLM functionality like structured interactions with Anthropic's Claude models.

[![Hex Version](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido)
[![Hex Docs](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/jido)
[![Mix Test](https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml/badge.svg)](https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/agentjido/jido/badge.svg?branch=main)](https://coveralls.io/github/agentjido/jido?branch=main)
[![Apache 2 License](https://img.shields.io/hexpm/l/jido)](https://opensource.org/licenses/Apache-2.0)

## Overview

Jido provides a robust foundation for building autonomous agents that can plan, execute, and adapt their behavior in distributed Elixir applications. Think of it as a toolkit for creating smart, composable workflows that can evolve and respond to their environment.

> ⚠️ **Status**: Jido is under active development. The API is stable for Actions, Workflows, Agents and Sensors. We are actively working on the Agent Server and Supervisor for the 1.1 release.

## Key Features

- 🧩 **Composable Actions**: Build complex behaviors from simple, reusable actions
- 🤖 **Autonomous Agents**: Self-directing entities that plan and execute workflows
- 📡 **Real-time Sensors**: Event-driven data gathering and monitoring
- 🔄 **Adaptive Learning**: Agents can modify their capabilities at runtime
- 📊 **Built-in Telemetry**: Comprehensive observability and debugging
- ⚡ **Distributed by Design**: Built for multi-node Elixir clusters
- 🧪 **Testing Tools**: Rich helpers for unit and property-based testing

## Installation

Add Jido to your dependencies:

```elixir
def deps do
  [
    {:jido, "~> 1.0.0"}
  ]
end
```

## Core Concepts

### Actions

Actions are the fundamental building blocks in Jido. Each Action is a discrete, reusable unit of work with a clear interface:

```elixir
defmodule MyApp.Actions.FormatUser do
  use Jido.Action,
    name: "format_user",
    description: "Formats user data by trimming whitespace and normalizing email",
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
```

[Learn more about Actions →](guides/actions.md)

### Workflows

Workflows chain Actions together to accomplish complex tasks. Jido handles data flow and error handling between steps:

```elixir
alias MyApp.Actions.{FormatUser, EnrichUserData, NotifyUser}

{:ok, result} = Jido.Workflow.Chain.chain(
  [FormatUser, EnrichUserData, NotifyUser],
  %{
    name: "John Doe ",
    email: "JOHN@EXAMPLE.COM"
  }
)
```

[Learn more about Workflows →](guides/actions.md#combining-actions-into-a-workflow)

### Agents

Agents are stateful entities that can plan and execute Actions. They maintain their state through a schema and can adapt their behavior:

```elixir
defmodule MyApp.CalculatorAgent do
  use Jido.Agent,
    name: "calculator",
    description: "An adaptive calculating agent",
    actions: [
      MyApp.Actions.Add,
      MyApp.Actions.Multiply,
      Jido.Actions.Directives.RegisterAction
    ],
    schema: [
      value: [type: :float, default: 0.0],
      operations: [type: {:list, :atom}, default: []]
    ]

  def on_after_run(agent, result) do
    # Track which operations we've used
    ops = [result.action | agent.state.operations] |> Enum.uniq()
    {:ok, %{agent | state: %{agent.state | operations: ops}}}
  end
end
```

[Learn more about Agents →](guides/agents.md)

### Sensors

Sensors provide real-time monitoring and data gathering for your agents:

```elixir
defmodule MyApp.Sensors.OperationCounter do
  use Jido.Sensor,
    name: "operation_counter",
    description: "Tracks operation usage metrics",
    schema: [
      emit_interval: [type: :pos_integer, default: 1000]
    ]

  def mount(opts) do
    {:ok, Map.merge(opts, %{counts: %{}})}
  end

  def handle_info({:operation, name}, state) do
    new_counts = Map.update(state.counts, name, 1, & &1 + 1)
    {:noreply, %{state | counts: new_counts}}
  end
end
```

[Learn more about Sensors →](guides/sensors.md)

## Running in Production

Start your agents under supervision:

```elixir
# In your application.ex
children = [
  {Registry, keys: :unique, name: Jido.AgentRegistry},
  {Phoenix.PubSub, name: MyApp.PubSub},
  {Jido.Agent.Supervisor, pubsub: MyApp.PubSub},
  {Jido.Agent.Server, 
    agent: MyApp.CalculatorAgent.new(),
    name: "calculator_1"
  }
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Example Use Cases

- **Service Orchestration**: Coordinate complex workflows across multiple services
- **Data Processing**: Build adaptive ETL pipelines that evolve with your data
- **Business Automation**: Model complex business processes with autonomous agents
- **System Monitoring**: Create smart monitoring agents that adapt to system behavior
- **Transaction Management**: Handle multi-step transactions with built-in compensation
- **Event Processing**: Process and react to event streams in real-time

## Documentation

- [📘 Getting Started Guide](guides/getting-started.md)
- [🧩 Actions & Workflows](guides/actions.md)
- [🤖 Building Agents](guides/agents.md)
- [📡 Sensors & Monitoring](guides/sensors.md)
- [🔄 Agent Directives](guides/directives.md)

## Contributing

We welcome contributions! Here's how to get started:

1. Fork the repository
2. Run tests: `mix test`
3. Run quality checks: `mix quality`
4. Submit a PR

Please include tests for any new features or bug fixes.

See our [Contributing Guide](CONTRIBUTING.md) for detailed guidelines.

## Testing

Jido is built with a test-driven mindset and provides comprehensive testing tools for building reliable agent systems. Our testing philosophy emphasizes:

- Thorough test coverage for core functionality
- Property-based testing for complex behaviors
- Regression tests for every bug fix
- Extensive testing helpers and utilities

### Testing Utilities

Jido provides several testing helpers:
- `Jido.TestSupport` - Common testing utilities
- Property-based testing via StreamData
- Mocking support through Mimic
- PubSub testing helpers
- Signal assertion helpers

### Running Tests

```bash
# Run the test suite
mix test

# Run with coverage reporting
mix test --cover

# Run the full quality check suite
mix quality
```

While we strive for 100% test coverage, we prioritize meaningful tests that verify behavior over simple line coverage. Every new feature and bug fix includes corresponding tests to prevent regressions.

## License

Apache License 2.0 - See [LICENSE.md](LICENSE.md) for details.

## Support

- 📚 [Documentation](https://hexdocs.pm/jido)
- 💬 [GitHub Discussions](https://github.com/agentjido/jido/discussions)
- 🐛 [Issue Tracker](https://github.com/agentjido/jido/issues)