# Jido (自動)

自動 (Jido) - A flexible framework for building distributed Agents and Workflows in Elixir.

[![Hex Version](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido)
[![Hex Docs](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/jido)
[![Mix Test](https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml/badge.svg)](https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml)
[![Apache 2 License](https://img.shields.io/hexpm/l/jido)](https://opensource.org/licenses/Apache-2.0)

## Current Status

Jido is under active development. The API of this library is usable, but not stable. We are actively working on stabilizing the current API and preparing for a 1.0 release.

We welcome feedback and contributions! Please feel free to open an issue or submit a PR.

## Features

- **Actions**: Discrete, composable units of functionality with consistent interfaces
- **Workflows**: Robust execution server with logging, telemetry, and error handling
- **Agents**: Stateful autonomous entities that can plan and execute workflows
- **Sensors**: Event-driven data gathering components
- **Signals**: Cloud Events-based messaging between components
- **Flexible Planning**: Pluggable planners for agent decision making
- **Comprehensive Testing**: Rich testing tools and helpers
- **Observable**: Built-in telemetry and debugging tools

## Installation

Add `jido` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 0.1.0"}
  ]
end
```

## Getting Started

### Creating an Action

Actions are the basic building blocks in Jido. Here's a simple calculator action:

```elixir
defmodule MyApp.Actions.Add do
  use Jido.Action,
    name: "add",
    description: "Adds two numbers",
    schema: [
      value: [type: :number, required: true],
      amount: [type: :number, required: true]
    ]

  @impl true 
  def run(%{value: value, amount: amount}, _context) do
    {:ok, %{result: value + amount}}
  end
end
```

### Creating a Simple Agent

Agents combine actions into autonomous behaviors:

```elixir
defmodule MyApp.SimpleAgent do
  use Jido.Agent,
    name: "SimpleBot",
    description: "A simple agent that performs basic tasks",
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100]
    ]

  @impl true
  def plan(%__MODULE__{} = agent) do
    {:ok, [
        {MyApp.Actions.Basic.Log, message: "Hello, world!"},
        {MyApp.Actions.Basic.Sleep, duration: 50},
        {MyApp.Actions.Basic.Log, message: "Goodbye, world!"}
     ]}
  end
end
```

### Starting an Agent Server

Start an agent worker under your supervision tree:

```elixir
# In your application.ex
children = [
  {Registry, keys: :unique, name: Jido.AgentRegistry},
  {Jido.Agent.Supervisor, pubsub: MyApp.PubSub}
]

# Start an agent instance
{:ok, pid} = Jido.Agent.Server.start_link(MyApp.SimpleAgent.new())
```

## Contributing

We welcome contributions! Please feel free to submit a PR.

To run tests:

```bash
mix test
```

## License

Apache License 2.0 - See [LICENSE.md](LICENSE.md) for details.