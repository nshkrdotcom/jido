# Jido (自動)

自動 (Jido) is a Japanese word meaning "automatic" or "automated", where:
- 自 (ji) means "self"
- 動 (dō) means "movement" or "motion"

Jido is a SDK for building AI Agents and AI Workflows.  It provides a flexible, composable framework for creating autonomous agents that can plan, execute, and adapt their actions in response to changing conditions. Jido’s architecture leverages pluggable components—Actions, Sensors, Agents, Planners, and more—to enable resilient, distributed, and intelligent systems.

## Features

- **Modular Components:**  
  Jido's functionality is built around the following components:
  - Actions: Small reusable workflows
  - Workflows: Action runtime and execution context, including logging, telemetry, and error handling
  - Workflow Chains & Graphs: Tools to dynamically build and execute workflows at runtime
  - Planners: Adapater for dynamically building workflow chains for Agents
  - Agents: Functional entities with state and allow list of workflows
  - Autobots: GenServer wrapper around Agents
  - Signals: Envelope for passing messages between agents, based on the Cloud Events specification
  - Sensors: Data gatherering GenServers that can be used to feed data into agents
  - Machines: GenStage based data streaming to a pool of Autobots

- **Distributed & Scalable:**  
  Jido is designed to be distributed and scalable.  Each component can be used idiomatically in Elixir, but has also been extended to support distributed workflow and scaling with PubSub and GenStage.

- **Flexible Planning Behavior:**  
  Jido provides a flexible planning behavior that can be extended to support custom workflows.  You can easily define your own planning algorithms for your Agents.

- **Testing & Debugging:**  
  Jido provides a flexible testing framework that allows you to test your Agents and workflows in isolation.  You can also use the built-in debug tools to visualize the execution of your workflows and workflows.

- **Telemetry & Observability:**  
  Workflows and workflows integrate telemetry events, making it easier to monitor, debug, and understand agent behavior.

## Getting Started

### Installation

Add `jido` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 0.1.0"}
  ]
end
```

### Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido>.


## Todo

- [ ] Build, test and document Actions
- [ ] Build, test and document Basic Actions
- [ ] Build, test and document File Actions
- [ ] Build, test and document Simplebot Actions
- [ ] Build, test and document Langchain & Instructor Actions
- [ ] Build, test and document Workflows
- [ ] Build, test and document Workflow Chains, Closures and Tools 
- [ ] Workflow Graphs
- [ ] Advanced Workflow Steps - Map, Filter, Reduce, etc.
- [ ] Workflow Tools
- [ ] Planner Behavior
- [ ] Simple Planner
- [ ] Advanced Planner
- [ ] Signals
- [ ] Sensors
- [ ] Autobots
- [ ] Machines
- [ ] Supervisory Bots
- [ ] Bot delegation