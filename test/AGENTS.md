# Jido Test Guide

## Quick Rules

- **No `Process.sleep`** — use `JidoTest.Eventually` for async assertions
- **Test behavior, not logs** — skip `ExUnit.CaptureLog` unless necessary
- **One assertion per test** when possible, with clear names
- **Use test support modules** from `test/support/` (see below)

---

## Run Tests

```bash
mix test                      # All tests
mix test test/path/to/file    # Single file
mix test --cover              # With 80%+ coverage threshold
mix test --include example    # Run example tests
```

---

## Support Modules

### `JidoTest.Case` — Isolated Jido Instance Per Test

```elixir
use JidoTest.Case, async: true  # Each test gets fresh jido instance
```

**Context keys:**

- `jido` — Name of the Jido instance (atom)
- `jido_pid` — PID of the Jido supervisor

**Helper functions:**

| Function                         | Purpose                                |
| -------------------------------- | -------------------------------------- |
| `start_test_agent(ctx, Agent)`   | Start agent under test's Jido instance |
| `start_server(ctx, Agent, opts)` | Start AgentServer with auto-cleanup    |
| `test_registry(ctx)`             | Get registry name for test's Jido      |
| `test_task_supervisor(ctx)`      | Get task supervisor name               |
| `test_agent_supervisor(ctx)`     | Get agent supervisor name              |
| `unique_id(prefix)`              | Generate unique ID: `"prefix-12345"`   |
| `signal(type, data, opts)`       | Create test signal with `/test` source |

### `JidoTest.Eventually` — Async Polling (Auto-imported by Case)

```elixir
# Basic polling (default: 500ms timeout, 5ms interval)
eventually(fn -> some_condition?() end, timeout: 1000)

# Poll AgentServer state
eventually_state(pid, fn state -> state.counter > 0 end)

# Assert macros
assert_eventually Process.alive?(pid)
refute_eventually some_condition?()
```

### `JidoTest.Support.TestTracer` — Span Tracing

```elixir
TestTracer.start_link()
TestTracer.get_spans()   # Returns [{:start, ref, prefix, meta}, {:stop, ref, measurements}, ...]
TestTracer.clear()
```

---

## Test Agents (`JidoTest.TestAgents`)

| Agent                          | Purpose                                                  |
| ------------------------------ | -------------------------------------------------------- |
| `Minimal`                      | Bare agent with no routes (unit tests)                   |
| `Counter`                      | State + routes: increment, decrement, record, slow, fail |
| `Basic`                        | Agent with category, tags, version metadata              |
| `Hook`                         | Agent with `on_after_cmd/3` hook                         |
| `CustomStrategy`               | Agent with custom `CountingStrategy`                     |
| `StrategyWithOpts`             | Strategy with options `{Strategy, opts}`                 |
| `ZoiSchema`                    | Agent using Zoi schema instead of NimbleOptions          |
| `WithCustomStrategy`           | Agent with `InitDirectiveStrategy` (emits on init)       |
| `TestSkillWithRoutes`          | Skill with routes for skill routing tests                |
| `AgentWithSkillRoutes`         | Agent with attached skill                                |
| `AgentWithMultiInstanceSkills` | Agent with multiple skill instances                      |

---

## Test Actions (`JidoTest.TestActions`)

### State Modification

| Action            | Behavior                                       |
| ----------------- | ---------------------------------------------- |
| `IncrementAction` | Add `:amount` (default 1) to `:counter`        |
| `DecrementAction` | Subtract `:amount` (default 1) from `:counter` |
| `RecordAction`    | Append `:message` to `:messages` list          |
| `BasicAction`     | Return `%{value: value}` from params           |
| `Add`             | Add `:amount` to `:value`                      |
| `NoSchema`        | Action without schema validation               |

### StateOp Actions

| Action               | StateOp                                              |
| -------------------- | ---------------------------------------------------- |
| `SetStateAction`     | `SetState{attrs: %{extra: "state"}}`                 |
| `ReplaceStateAction` | `ReplaceState{state: %{...}}`                        |
| `DeleteKeysAction`   | `DeleteKeys{keys: [:to_delete, :also_delete]}`       |
| `SetPathAction`      | `SetPath{path: [:nested, :deep, :value], value: 42}` |
| `DeletePathAction`   | `DeletePath{path: [:nested, :to_remove]}`            |

### Directive Actions

| Action              | Directive                                                |
| ------------------- | -------------------------------------------------------- |
| `EmitAction`        | Returns `Directive.emit(signal)`                         |
| `MultiEffectAction` | Returns `[Directive.emit(...), Directive.schedule(...)]` |

### Error & Async

| Action          | Behavior                             |
| --------------- | ------------------------------------ |
| `FailingAction` | Always returns `{:error, reason}`    |
| `SlowAction`    | Sleeps for `:delay_ms` (default 100) |

---

## Test Patterns

### Pure Agent (no server)

```elixir
defmodule JidoTest.MyFeatureTest do
  use JidoTest.Case, async: true

  test "cmd/2 updates state immutably" do
    agent = JidoTest.TestAgents.Counter.new()

    {updated, directives} = JidoTest.TestAgents.Counter.cmd(
      agent,
      {JidoTest.TestActions.IncrementAction, %{amount: 5}}
    )

    assert updated.state.counter == 5
    assert directives == []
    assert agent.state.counter == 0  # Original unchanged
  end
end
```

### AgentServer with Async Assertions

```elixir
defmodule JidoTest.ServerFeatureTest do
  use JidoTest.Case, async: true

  test "agent processes signal", %{jido: jido} do
    pid = start_server(%{jido: jido}, JidoTest.TestAgents.Counter)

    signal = signal("increment", %{amount: 3})
    {:ok, _agent} = Jido.AgentServer.call(pid, signal)

    eventually_state(pid, &(&1.counter == 3))
  end
end
```

### Signal Routing

```elixir
test "signal routes to correct action", %{jido: jido} do
  {:ok, pid} = Jido.start_agent(jido, JidoTest.TestAgents.Counter, id: unique_id())

  signal = signal("record", %{message: "hello"})
  {:ok, agent} = Jido.AgentServer.call(pid, signal)

  assert "hello" in agent.state.messages
end
```

### Directive Emission with Collector

```elixir
test "action emits signal", %{jido: jido} do
  {:ok, collector} = SignalCollector.start_link()
  on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

  {:ok, pid} = Jido.start_agent(jido, MyAgent,
    id: unique_id(),
    default_dispatch: {:pid, target: collector}
  )

  {:ok, _} = Jido.AgentServer.call(pid, signal("trigger"))

  eventually(fn -> length(SignalCollector.get_signals(collector)) >= 1 end)
end
```

### Parent-Child Patterns

```elixir
test "parent spawns child and receives response", %{jido: jido} do
  {:ok, parent_pid} = Jido.start_agent(jido, CoordinatorAgent, id: unique_id())

  signal = signal("spawn_worker", %{worker_tag: :worker_1, work_data: %{value: 5}})
  {:ok, _} = Jido.AgentServer.call(parent_pid, signal)

  eventually(fn ->
    case Jido.AgentServer.state(parent_pid) do
      {:ok, %{children: children}} -> Map.has_key?(children, :worker_1)
      _ -> false
    end
  end, timeout: 5_000)
end
```

---

## Avoid

| ❌ Don't                         | ✅ Do                                 |
| -------------------------------- | ------------------------------------- |
| `Process.sleep(100)`             | `eventually(fn -> ... end)`           |
| `ExUnit.CaptureLog`              | Test return values, state, directives |
| Multiple assertions per test     | Split into focused tests              |
| Test with real external services | Use mock adapters or collectors       |
| Hardcoded PIDs or IDs            | Use `unique_id()` helper              |

---

## Example Test Files

Reference these for patterns:

- `test/examples/counter_agent_test.exs` — Pure agent, cmd/2 basics
- `test/examples/state_ops_test.exs` — StateOp patterns
- `test/examples/emit_directive_test.exs` — Signal emission
- `test/examples/parent_child_test.exs` — SpawnAgent, emit_to_parent
- `test/examples/signal_routing_test.exs` — Route matching
