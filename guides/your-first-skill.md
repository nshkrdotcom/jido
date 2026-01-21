# Your First Skill

**After:** You can refactor "stuff your agent does" into a Skill with isolated state and routing.

## The Result

Here's what you'll build—a `CounterSkill` that tracks a counter in isolated state and routes signals to increment it:

```elixir
defmodule MyApp.CounterSkill do
  use Jido.Skill,
    name: "counter",
    state_key: :counter,
    actions: [MyApp.IncrementAction],
    schema: Zoi.object(%{
      value: Zoi.integer() |> Zoi.default(0),
      last_updated: Zoi.any() |> Zoi.optional()
    }),
    signal_patterns: ["counter.*"]

  @impl Jido.Skill
  def router(_config) do
    [{"counter.increment", MyApp.IncrementAction}]
  end
end
```

Attach it to an agent:

```elixir
defmodule MyApp.MyAgent do
  use Jido.Agent,
    name: "my_agent",
    skills: [MyApp.CounterSkill]
end
```

Send a signal:

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: MyApp.MyAgent, jido: MyApp.Jido)

signal = Jido.Signal.new!("counter.increment", %{amount: 5}, source: "/app")
{:ok, agent} = Jido.AgentServer.call(pid, signal)

agent.state.counter.value
#=> 5
```

The skill owns `agent.state.counter`—isolated from other skills.

## Building It Step by Step

### Step 1: Create the Action

Actions do the actual work. This action increments a counter:

```elixir
defmodule MyApp.IncrementAction do
  use Jido.Action,
    name: "increment",
    schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

  alias Jido.Agent.StateOp

  def run(%{amount: amount}, %{state: state}) do
    current = get_in(state, [:counter, :value]) || 0

    {:ok, %{},
     [
       %StateOp.SetPath{path: [:counter, :value], value: current + amount},
       %StateOp.SetPath{path: [:counter, :last_updated], value: DateTime.utc_now()}
     ]}
  end
end
```

### Step 2: Define the Skill

Wrap the action in a skill with state and routing:

```elixir
defmodule MyApp.CounterSkill do
  use Jido.Skill,
    name: "counter",
    state_key: :counter,
    actions: [MyApp.IncrementAction],
    schema: Zoi.object(%{
      value: Zoi.integer() |> Zoi.default(0),
      last_updated: Zoi.any() |> Zoi.optional()
    }),
    signal_patterns: ["counter.*"]

  @impl Jido.Skill
  def router(_config) do
    [{"counter.increment", MyApp.IncrementAction}]
  end
end
```

**Required options:**

| Option | Description |
|--------|-------------|
| `name` | Skill name (letters, numbers, underscores) |
| `state_key` | Atom key for skill state in agent |
| `actions` | List of action modules the skill provides |

**Key optional options:**

| Option | Description |
|--------|-------------|
| `schema` | Zoi schema for skill state with defaults |
| `signal_patterns` | Patterns this skill handles (e.g., `"counter.*"`) |

### Step 3: Attach to an Agent

```elixir
defmodule MyApp.MyAgent do
  use Jido.Agent,
    name: "my_agent",
    skills: [MyApp.CounterSkill]
end
```

When the agent is created, the skill's state is initialized under its `state_key`.

## State Isolation

Each skill gets its own namespace in `agent.state`:

```elixir
agent = MyApp.MyAgent.new()

agent.state
#=> %{
#=>   counter: %{value: 0, last_updated: nil}  # CounterSkill state
#=> }
```

With multiple skills:

```elixir
defmodule MyApp.MultiSkillAgent do
  use Jido.Agent,
    name: "multi_agent",
    skills: [
      MyApp.CounterSkill,
      MyApp.ChatSkill
    ]
end

agent = MyApp.MultiSkillAgent.new()

agent.state
#=> %{
#=>   counter: %{value: 0, last_updated: nil},  # CounterSkill
#=>   chat: %{messages: [], model: "gpt-4"}     # ChatSkill
#=> }
```

Skills can't accidentally overwrite each other's state.

## Signal Routing

The `router/1` callback maps signal types to actions:

```elixir
@impl Jido.Skill
def router(_config) do
  [
    {"counter.increment", MyApp.IncrementAction},
    {"counter.reset", MyApp.ResetAction}
  ]
end
```

When a signal arrives:

1. Router finds a matching pattern
2. The corresponding action runs via `cmd/2`
3. State operations update `agent.state`

**Complete example:**

```elixir
# Start the agent
{:ok, pid} = Jido.AgentServer.start_link(agent: MyApp.MyAgent, jido: MyApp.Jido)

# Send increment signal
signal = Jido.Signal.new!("counter.increment", %{amount: 10}, source: "/app")
{:ok, agent} = Jido.AgentServer.call(pid, signal)

agent.state.counter.value
#=> 10

# Send another
signal = Jido.Signal.new!("counter.increment", %{amount: 5}, source: "/app")
{:ok, agent} = Jido.AgentServer.call(pid, signal)

agent.state.counter.value
#=> 15
```

## Configuration

Pass per-agent configuration with the `{Skill, config}` form:

```elixir
defmodule MyApp.ConfigurableSkill do
  use Jido.Skill,
    name: "configurable",
    state_key: :configurable,
    actions: [MyApp.SomeAction],
    config_schema: Zoi.object(%{
      max_value: Zoi.integer() |> Zoi.default(100)
    })

  @impl Jido.Skill
  def mount(_agent, config) do
    {:ok, %{initialized_at: DateTime.utc_now(), max: config[:max_value]}}
  end
end
```

Attach with config:

```elixir
defmodule MyApp.ConfiguredAgent do
  use Jido.Agent,
    name: "configured_agent",
    skills: [
      {MyApp.ConfigurableSkill, %{max_value: 500}}
    ]
end

agent = MyApp.ConfiguredAgent.new()
agent.state.configurable.max
#=> 500
```

The `mount/2` callback receives the config and can use it to initialize state.

## Next Steps

- [Skills Reference](skills.md) — Full API reference and lifecycle callbacks
- [Signals & Routing](signals.md) — Signal patterns and routing rules
- [Actions](actions.md) — How actions transform state and emit directives
