<p align="center">
  <h1>Jido (自動)</h1>
</p>

<p align="center">
Autonomous agent framework for Elixir, built for distributed, autonomous behavior and dynamic workflows.<br />

Reliable, observable, and loaded with <a href="#features">sophisticated agent features</a>.<br />

The name "Jido" (自動) comes from the Japanese word meaning "automatic" or "automated", where 自 (ji) means "self" and 動 (dō) means "movement".

</p>

<p align="center">
  <a href="https://hex.pm/packages/jido">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/jido.svg">
  </a>

  <a href="https://hexdocs.pm/jido">
    <img alt="Hex Docs" src="http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat">
  </a>

  <a href="https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml">
    <img alt="Mix Test" src="https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml/badge.svg">
  </a>

  <a href="https://coveralls.io/github/agentjido/jido?branch=main">
    <img alt="Coverage Status" src="https://coveralls.io/repos/github/agentjido/jido/badge.svg?branch=main">
  </a>

  <a href="https://opensource.org/licenses/Apache-2.0">
    <img alt="Apache 2 License" src="https://img.shields.io/hexpm/l/jido">
  </a>
</p>

## Table of Contents

- [Features](#features)
- [Do You Need an Agent?](#do-you-need-an-agent)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Core Concepts](#core-concepts)
- [Learning](#learning)
- [Community](#community)
- [Contributing](#contributing)

---

> [!NOTE]
> This README is for the unreleased main branch. Please reference the [official documentation on hexdocs](https://hexdocs.pm/jido) for the latest stable release.

---

## Features

Jido's primary goals are **reliability**, **composability**, and **observability** in agent-based systems.

#### Core Capabilities

- 🧩 **Composable Actions**

  - Build complex behaviors from discrete, validated actions
  - Compose Actions at runtime into dynamic workflows
  - Comprehensive error handling and compensation
  - Clear contracts with schema validation

- 🔄 **Flexible Messaging via Signals**

  - Cloudevents compatible messaging envelope
  - Asynchronous and synchronous request/response
  - Flexible routing and filtering
  - Adapter based output dispatching

- 🤖 **Autonomous Agents**

  - OTP-native agent process supervision
  - Asynchronous and synchronous request/response
  - Dynamic workflow control
  - State-aware self-directed behavior

- 📡 **Real-time Sensors**

  - Extension to consume external system events
  - Simple custom sensor development
  - Configurable event filtering

- 🧪 **Testing Tools**
  - Easily tested architecture
  - Behavioral verification
  - Mock sensors and actions
  - Integration test helpers

## Do You Need an Agent?

Agents are powerful but not always necessary. Consider using Jido when you need:

- Dynamic workflow orchestration
- Adaptive decision making
- Complex state management
- Autonomous operation
- Distributed coordination

[Learn more about when to use agents →](https://hexdocs.pm/jido/about/do-you-need-an-agent.html)

## Quick Start

Define and start an agent with a few lines of code. Direct it using Signals, and receive results via the Agent's PID:

```elixir
# First, define our Calculator agent with supported operations
iex> defmodule CalculatorAgent do
...>   use Jido.Agent,
...>     name: "calculator",
...>     actions: [Actions.Add, Actions.Subtract, Actions.Multiply, Actions.Divide]
...>   # Omitting the router that maps the "add" signal to the Add Action
...> end
{:module, CalculatorAgent, <<...>>, %{}}

# Start the agent process
iex> {:ok, pid} = CalculatorAgent.start_link()
{:ok, #PID<0.123.0>}

# Send a synchronous request to the agent
iex> {:ok, result} = CalculatorAgent.call(pid, Signal.new(%{type: "add", data: %{a: 1, b: 2}}))
{:ok, 3}

# Send an asynchronous request to the agent
iex> {:ok, request_id} = CalculatorAgent.cast(pid, Signal.new(%{type: "multiply", data: %{a: 2, b: 4}}))
{:ok, "req_abc123"}

# Receive the result of the asynchronous request
iex> flush()
{:jido_agent, "req_abc123", 8}
:ok
```

This example barely scratches the surface of what Jido can do. For more examples, see the [Getting Started Guide](guides/getting-started.livemd) and [Jido Workbench](https://github.com/agentjido/jido_workbench) to play with our growing catalog of real-life examples.

## Installation

Add Jido to your dependencies:

```elixir
def deps do
  [
    {:jido, "~> 1.0.0"}
  ]
end
```

You may also want to add Jido ecosystem dependencies:

- [jido_ai](https://github.com/agentjido/jido_ai) for LLM-driven agents
- [jido_chat](https://github.com/agentjido/jido_chat) for chat based messaging
- [jido_memory](https://github.com/agentjido/jido_memory) for persistent agent memory

You can see examples of each of these in the [Jido Workbench](https://github.com/agentjido/jido_workbench).

## Overview

Jido provides a robust foundation for building autonomous agents that can plan, execute, and adapt their behavior in distributed Elixir applications. Think of it as a toolkit for creating smart, composable workflows that can evolve and respond to their environment.

## Are You Sure You Need an Agent?

Agents are a hot topic right now, but they aren't a silver bullet. In particular, Large Language Models (LLMs) are powerful yet slow and costly—if your application doesn't require dynamic decision-making or complex planning, consider whether you really need an Agent at all.

- **LLMs aren't required for all tasks** — Avoid building them into your core logic unless necessary
- **Agents as Dynamic ETL** — Agents dynamically direct data ingestion, transformation, and output based on:
  - LLMs (e.g., GPT)
  - Classical planning algorithms (A\*, Behavior Trees, etc.)
- **Simplicity often wins** — If you don't need these dynamic behaviors, you probably don't need an Agent. This library is likely overkill compared to straightforward code.

### Our Definition of an Agent

An Agent is a system where LLMs _or_ classical planning algorithms dynamically direct their own processes. Some great definitions from the community:

- "Agents are Dynamic ETL processes directed by LLMs" — [YouTube](https://youtu.be/KY8n96Erp5Q?si=5Itt7QR11jgfWDTY&t=22)
- "Agents are systems where LLMs dynamically direct their own processes" — [Anthropic Research](https://www.anthropic.com/research/building-effective-agents)
- "AI Agents are programs where LLM outputs control the workflow" — [Hugging Face Blog](https://huggingface.co/blog/smolagents)

If your application doesn't involve dynamic workflows or data pipelines that change based on AI or planning algorithms, you can likely do more with less.

> 💡 **NOTE**: This library intends to support both LLM planning and Classical AI planning (ie. [Behavior Trees](https://github.com/jschomay/elixir-behavior-tree) as a design principle via Actions. See [`jido_ai`](https://github.com/agentjido/jido_ai) for example LLM actions.

_This space is evolving rapidly. Last updated 2025-01-01_

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

[Learn more about Actions →](guides/actions/overview.md)

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

[Learn more about Workflows →](guides/actions/workflows.md)

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

[Learn more about Agents →](guides/agents/overview.md)

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

[Learn more about Sensors →](guides/sensors/overview.md)

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

- [📘 Getting Started Guide](guides/getting-started.livemd)
- [🧩 Actions & Workflows](guides/actions/overview.md)
- [🤖 Building Agents](guides/agents/overview.md)
- [📡 Sensors & Monitoring](guides/sensors/overview.md)
- [🔄 Agent Directives](guides/agents/directives.md)

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
