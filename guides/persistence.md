# Persistence

**After:** Your agents can survive restarts (or you explicitly decide they shouldn't).

```elixir
# Configure persistence with InstanceManager
Jido.Agent.InstanceManager.child_spec(
  name: :sessions,
  agent: MyApp.SessionAgent,
  idle_timeout: :timer.minutes(15),
  persistence: [
    store: {Jido.Agent.Store.File, path: "priv/agent_state"}
  ]
)

# Agents hibernate on idle, thaw on demand
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")
# If agent was hibernated, state is restored automatically
```

This guide covers agent state persistence: when to use it, how to configure it, and how to build custom stores.

## The Store Behaviour

`Jido.Agent.Store` defines three callbacks for persisting agent state:

```elixir
@callback get(key(), opts()) :: {:ok, dump()} | :not_found | {:error, term()}
@callback put(key(), dump(), opts()) :: :ok | {:error, term()}
@callback delete(key(), opts()) :: :ok | {:error, term()}
```

Keys are typically `{agent_module, agent_id}` tuples. The `dump` is the serialized agent state (by default, the entire agent struct).

## Built-in Stores

### ETS Store — Fast, Ephemeral

In-memory storage using ETS. Data is lost when the BEAM stops.

```elixir
persistence: [
  store: {Jido.Agent.Store.ETS, table: :agent_cache}
]
```

**Use for:** Development, testing, and production scenarios where losing state on restart is acceptable.

**Characteristics:**
- Concurrent reads via `read_concurrency: true`
- Table created automatically if missing
- No serialization overhead (terms stored directly)

### File Store — Durable, Simple

File-based storage with atomic writes. Survives restarts.

```elixir
persistence: [
  store: {Jido.Agent.Store.File, path: "priv/agent_state"}
]
```

**Use for:** Production deployments, development with state preservation.

**Characteristics:**
- One file per agent (hashed filename)
- Atomic writes via temp file + rename
- Erlang term format (`:erlang.term_to_binary/1`)
- Directory created automatically

## InstanceManager Integration

The `Jido.Agent.InstanceManager` handles persistence automatically:

```elixir
# In your supervision tree
children = [
  Jido.Agent.InstanceManager.child_spec(
    name: :sessions,
    agent: MyApp.SessionAgent,
    idle_timeout: :timer.minutes(15),
    persistence: [
      store: {Jido.Agent.Store.File, path: "priv/sessions"}
    ]
  )
]
```

### Lifecycle

1. **Get/Start**: `InstanceManager.get/3` looks up by key in Registry
2. **Thaw**: If not running but persistence exists, state is restored
3. **Fresh**: If no persisted state, starts a fresh agent
4. **Attach**: Callers track interest via `AgentServer.attach/1`
5. **Idle**: When all attachments detach, idle timer starts
6. **Hibernate**: On timeout, agent state is persisted then process stops

```elixir
# Get or start an agent (thaws if hibernated)
{:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")

# Track this caller's interest
:ok = Jido.AgentServer.attach(pid)

# When done, detach (starts idle timer if no other attachments)
:ok = Jido.AgentServer.detach(pid)
```

## What Gets Persisted

By default, the entire agent struct is persisted:

- `agent.id`
- `agent.state` (your application state)
- `agent.__struct__` (agent module)

### Custom Serialization

Implement `dump/2` and `load/2` callbacks in your agent for custom serialization:

```elixir
defmodule MyApp.SessionAgent do
  use Jido.Agent,
    name: "session_agent",
    schema: [
      user_id: [type: :string, required: true],
      cart: [type: {:list, :map}, default: []]
    ]

  @impl true
  def dump(agent, _context) do
    # Persist only essential state
    {:ok, %{
      id: agent.id,
      user_id: agent.state.user_id,
      cart: agent.state.cart,
      version: 1
    }}
  end

  @impl true
  def load(data, _context) do
    # Reconstruct from persisted data
    {:ok, agent} = new(id: data.id)
    {:ok, set(agent, %{user_id: data.user_id, cart: data.cart})}
  end
end
```

## Schema Evolution

When your agent schema changes, handle version migrations in `load/2`:

```elixir
def load(%{version: 1} = data, context) do
  # Migrate v1 to current schema
  migrated = %{
    id: data.id,
    user_id: data.user_id,
    cart: data.cart,
    preferences: %{}  # New field with default
  }
  load(%{migrated | version: 2}, context)
end

def load(%{version: 2} = data, _context) do
  {:ok, agent} = new(id: data.id)
  {:ok, set(agent, Map.drop(data, [:version, :id]))}
end
```

## Direct Persistence API

Use `Jido.Agent.Persistence` for direct control outside InstanceManager:

```elixir
config = [store: {Jido.Agent.Store.File, path: "priv/agents"}]

# Hibernate an agent
:ok = Jido.Agent.Persistence.hibernate(config, MyAgent, "agent-123", agent)

# Thaw an agent
case Jido.Agent.Persistence.thaw(config, MyAgent, "agent-123") do
  {:ok, agent} -> agent
  :not_found -> MyAgent.new!(id: "agent-123")
  {:error, reason} -> raise "Failed to thaw: #{inspect(reason)}"
end
```

### Custom Key Function

Override the default key generation:

```elixir
config = [
  store: {Jido.Agent.Store.File, path: "priv/agents"},
  key_fun: fn module, id -> "#{module}:#{id}" end
]
```

## Example: Persist Workflow Results

A workflow agent that persists progress and resumes after restart:

```elixir
defmodule MyApp.WorkflowAgent do
  use Jido.Agent,
    name: "workflow_agent",
    schema: [
      workflow_id: [type: :string, required: true],
      steps_completed: [type: {:list, :atom}, default: []],
      current_step: [type: :atom, default: :init],
      results: [type: :map, default: %{}]
    ]

  @impl true
  def dump(agent, _context) do
    {:ok, %{
      id: agent.id,
      workflow_id: agent.state.workflow_id,
      steps_completed: agent.state.steps_completed,
      current_step: agent.state.current_step,
      results: agent.state.results,
      version: 1
    }}
  end

  @impl true
  def load(data, _context) do
    {:ok, agent} = new(id: data.id)
    {:ok, set(agent, %{
      workflow_id: data.workflow_id,
      steps_completed: data.steps_completed,
      current_step: data.current_step,
      results: data.results
    })}
  end
end
```

Usage with InstanceManager:

```elixir
# Start workflow (or resume if hibernated)
{:ok, pid} = Jido.Agent.InstanceManager.get(:workflows, "order-456",
  initial_state: %{workflow_id: "order-456"}
)

# Process steps - state persists on idle
Jido.AgentServer.call(pid, Signal.new!("workflow.step.complete", %{step: :validate}))

# After restart, agent resumes from last known state
{:ok, pid} = Jido.Agent.InstanceManager.get(:workflows, "order-456")
{:ok, state} = Jido.AgentServer.state(pid)
# state.agent.state.steps_completed => [:validate]
```

## Custom Store: Redis Example

Implement `Jido.Agent.Store` for your infrastructure:

```elixir
defmodule MyApp.RedisStore do
  @behaviour Jido.Agent.Store

  @impl true
  def get(key, opts) do
    pool = Keyword.get(opts, :pool, :redix)
    redis_key = serialize_key(key)

    case Redix.command(pool, ["GET", redis_key]) do
      {:ok, nil} -> :not_found
      {:ok, data} -> {:ok, :erlang.binary_to_term(data, [:safe])}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def put(key, dump, opts) do
    pool = Keyword.get(opts, :pool, :redix)
    ttl = Keyword.get(opts, :ttl, 3600)
    redis_key = serialize_key(key)
    data = :erlang.term_to_binary(dump)

    case Redix.command(pool, ["SETEX", redis_key, ttl, data]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key, opts) do
    pool = Keyword.get(opts, :pool, :redix)
    redis_key = serialize_key(key)

    case Redix.command(pool, ["DEL", redis_key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp serialize_key({module, id}) do
    "jido:agent:#{module}:#{id}"
  end
end
```

Use it:

```elixir
Jido.Agent.InstanceManager.child_spec(
  name: :sessions,
  agent: MyApp.SessionAgent,
  persistence: [
    store: {MyApp.RedisStore, pool: :redix, ttl: 86_400}
  ]
)
```

## When NOT to Persist

**Ephemeral workers** don't need persistence:

```elixir
# Fire-and-forget task agents
Jido.Agent.InstanceManager.child_spec(
  name: :tasks,
  agent: MyApp.TaskAgent,
  idle_timeout: :timer.seconds(30)
  # No persistence: option - agent dies on idle, no restore
)
```

Skip persistence when:

- **Agents are stateless** — they fetch state from external sources on start
- **State is cheap to rebuild** — re-running init is faster than I/O
- **Short-lived workers** — task duration < hibernate overhead
- **Sensitive data** — secrets shouldn't hit disk/cache
- **High-churn agents** — frequent start/stop makes persistence overhead costly

## Related

- [Runtime](runtime.md) — AgentServer and process-based execution
- [Configuration](configuration.md) — Jido instance configuration
- [Testing](testing.md) — Testing patterns (ETS store for tests)
