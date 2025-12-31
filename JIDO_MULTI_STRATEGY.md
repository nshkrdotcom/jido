# Multi-Strategy Support for Jido Agents

## Executive Summary

**Recommendation:** Preserve the current "one strategy per agent module" contract and introduce **meta-strategy modules** that internally compose, chain, or switch between multiple child strategies. This approach supports all multi-strategy use cases while maintaining FP purity and requiring zero changes to the core `Agent` API.

---

## Current State

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    strategy: Jido.Agent.Strategy.Direct  # ONE strategy, compile-time fixed
end

# Core contract - pure function
{agent, directives} = MyAgent.cmd(agent, action)
```

**Constraints:**
- Strategy is compile-time fixed per agent module via `strategy/0`
- `cmd/2` delegates to `strategy().cmd/3`
- Strategy state lives under `agent.state.__strategy__`
- Directives are external effects only - never modify agent state

---

## Four Multi-Strategy Use Cases

| Use Case | Description | Example |
|----------|-------------|---------|
| **Multiple Strategies** | Run several strategies concurrently or sequentially | React + BehaviorTree both active |
| **Strategy Composition** | Chain strategies in a pipeline | Planner → Executor → Validator |
| **Dynamic Switching** | Change active strategy at runtime | Start in `:planning`, switch to `:execution` |
| **Nested/Meta Strategies** | Strategies that orchestrate other strategies | Supervisor strategy managing child strategies |

---

## Recommended Approach: Meta-Strategies

### Core Idea

Treat "multi-strategy" as an implementation detail of a **single top-level strategy module** that satisfies `Jido.Agent.Strategy`. The `Agent` macro and `cmd/2` remain unchanged:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    strategy: {Jido.Agent.Strategy.Multi,
               strategies: [
                 {:react, MyReactStrategy, react_opts},
                 {:bt, MyBehaviorTreeStrategy, bt_opts}
               ],
               mode: :pipeline}  # or :fanout, :switch
end
```

### Why This Works

1. **FP Purity Preserved**: `cmd/2` stays pure - `(agent, action) -> {agent, directives}`
2. **No API Changes**: Agent modules still declare one strategy
3. **Composition is Just Function Composition**:
   ```elixir
   def cmd(agent, instrs, ctx) do
     {a1, d1} = Step1.run(agent, instrs, ctx)
     {a2, d2} = Step2.run(a1, instrs, ctx)
     {a2, d1 ++ d2}
   end
   ```
4. **State Management Stays Simple**: One `__strategy__` key, structured as a tree

---

## Implementation Design

### 1. `Jido.Agent.Strategy.Multi` Module

```elixir
defmodule Jido.Agent.Strategy.Multi do
  @behaviour Jido.Agent.Strategy
  
  @impl true
  def init(agent, ctx) do
    children = ctx.strategy_opts[:strategies] || []
    mode = ctx.strategy_opts[:mode] || :pipeline
    
    # Initialize all child strategies
    {agent, child_states} = initialize_children(agent, children, ctx)
    
    strategy_state = %{
      module: __MODULE__,
      mode: mode,
      active: first_child_key(children),
      children: child_states,
      status: :ready
    }
    
    {put_strategy_state(agent, strategy_state), []}
  end
  
  @impl true
  def cmd(agent, instructions, ctx) do
    case get_mode(agent) do
      :pipeline -> run_pipeline(agent, instructions, ctx)
      :fanout   -> run_fanout(agent, instructions, ctx)
      :switch   -> run_active(agent, instructions, ctx)
    end
  end
  
  defp run_pipeline(agent, instructions, ctx) do
    children = get_children(agent)
    
    Enum.reduce(children, {agent, []}, fn {_key, child}, {acc_agent, acc_directives} ->
      {new_agent, new_directives} = child.module.cmd(acc_agent, instructions, child_ctx(child, ctx))
      {new_agent, acc_directives ++ new_directives}
    end)
  end
  
  defp run_active(agent, instructions, ctx) do
    active_key = get_active(agent)
    child = get_child(agent, active_key)
    child.module.cmd(agent, instructions, child_ctx(child, ctx))
  end
end
```

### 2. State Structure Under `__strategy__`

```elixir
agent.state.__strategy__ = %{
  module: Jido.Agent.Strategy.Multi,
  mode: :pipeline,
  active: :react,  # for :switch mode
  children: %{
    react: %{module: MyReactStrategy, status: :running, result: nil, ...},
    bt: %{module: MyBTStrategy, status: :idle, ...}
  },
  status: :running,
  result: nil
}
```

### 3. Nested State Helpers

```elixir
defmodule Jido.Agent.Strategy.NestedState do
  @moduledoc "Helpers for meta-strategies to manage child strategy state."
  
  def get_child_state(agent, child_key) do
    get_in(agent.state, [:__strategy__, :children, child_key])
  end
  
  def put_child_state(agent, child_key, child_state) do
    put_in(agent.state, [:__strategy__, :children, child_key], child_state)
  end
  
  def update_child_state(agent, child_key, fun) do
    update_in(agent.state, [:__strategy__, :children, child_key], fun)
  end
end
```

---

## Mode Behaviors

### Pipeline Mode (`:pipeline`)

Sequential chaining - output of strategy A feeds into strategy B:

```
Action → [StrategyA] → [StrategyB] → [StrategyC] → {agent, directives}
```

- Directives concatenated in order
- Each strategy sees agent state modified by previous strategies
- Use case: Planner → Executor → Validator

### Fanout Mode (`:fanout`)

All strategies process the same action independently:

```
         ┌→ [StrategyA] → directives_a
Action → ├→ [StrategyB] → directives_b  → merge → {agent, all_directives}
         └→ [StrategyC] → directives_c
```

- All directives collected
- State merging policy configurable (last-wins, merge, conflict-error)
- Use case: Multiple behaviors responding to same event

### Switch Mode (`:switch`)

Only one strategy active at a time:

```
         ┌→ [StrategyA] (inactive)
Action → ├→ [StrategyB] (ACTIVE) → {agent, directives}
         └→ [StrategyC] (inactive)
```

- `__strategy__.active` determines which child runs
- Switching via special actions or state conditions
- Use case: State machines, phase-based agents

---

## Directive Handling

### Merge Rules

1. **Concatenation**: Default - directives appended in child order
2. **First-Wins**: For exclusive directives (e.g., `%Stop{}`), only first kept
3. **Tagging**: Optionally tag directives with source child for tracing

```elixir
defp merge_directives(directive_lists, opts) do
  case opts[:merge_strategy] do
    :concat -> List.flatten(directive_lists)
    :first_stop -> take_until_stop(List.flatten(directive_lists))
    :tagged -> tag_with_source(directive_lists)
  end
end
```

### Conflict Resolution

For conflicting directives:
- Multiple `%Stop{}`: First one wins, rest discarded
- Multiple `%Schedule{}` with same delay: Either allow all or dedupe
- `%Error{}`: Typically collected, not deduplicated

---

## Usage Examples

### Example 1: React + Behavior Tree

```elixir
defmodule HybridAgent do
  use Jido.Agent,
    name: "hybrid_agent",
    strategy: {Jido.Agent.Strategy.Multi,
               mode: :switch,
               strategies: [
                 {:react, Jido.Agent.Strategy.React, [max_steps: 10]},
                 {:bt, MyBehaviorTreeStrategy, [tree: :patrol_tree]}
               ],
               initial: :react}
end

# Start in react mode
agent = HybridAgent.new()

# Process with current active strategy
{agent, directives} = HybridAgent.cmd(agent, SomeAction)

# Switch to behavior tree mode
{agent, _} = HybridAgent.cmd(agent, {:switch_strategy, :bt})
```

### Example 2: Pipeline - Plan Then Execute

```elixir
defmodule PlanExecuteAgent do
  use Jido.Agent,
    name: "plan_execute_agent",
    strategy: {Jido.Agent.Strategy.Multi,
               mode: :pipeline,
               strategies: [
                 {:planner, PlannerStrategy, []},
                 {:executor, ExecutorStrategy, []}
               ]}
end
```

### Example 3: Nested Meta-Strategies

```elixir
defmodule ComplexAgent do
  use Jido.Agent,
    name: "complex_agent",
    strategy: {Jido.Agent.Strategy.Multi,
               mode: :switch,
               strategies: [
                 {:exploration, {Jido.Agent.Strategy.Multi,
                   mode: :pipeline,
                   strategies: [
                     {:sensor, SensorStrategy, []},
                     {:mapper, MapperStrategy, []}
                   ]}},
                 {:exploitation, ExploitStrategy, []}
               ]}
end
```

---

## Comparison with Alternatives

### Alternative 1: Multiple Top-Level Strategies

```elixir
# NOT RECOMMENDED
use Jido.Agent,
  strategies: [StrategyA, StrategyB]  # Multiple at agent level
```

**Problems:**
- Requires changing core `Agent` module
- Need multiple `__strategy__` slots or namespacing everywhere
- Breaks existing strategies that assume single `__strategy__`
- State clobbering between strategies
- API breakage for existing code

**Verdict:** ❌ High complexity, marginal benefit over meta-strategies

### Alternative 2: Runtime Strategy Registration

```elixir
# NOT RECOMMENDED
Agent.register_strategy(agent, :aux, NewStrategy)
```

**Problems:**
- Mutates agent's strategy configuration
- Complicates the pure functional model
- State management becomes dynamic and harder to reason about

**Verdict:** ❌ Breaks FP purity

### Alternative 3: Strategy Protocol Dispatch

```elixir
# NOT RECOMMENDED
defprotocol StrategyDispatch do
  def cmd(strategy, agent, action)
end
```

**Problems:**
- Over-engineering for the use case
- Doesn't solve composition/chaining
- Adds indirection without clear benefit

**Verdict:** ❌ Adds complexity without solving the core problem

---

## FP Purity Analysis

### Meta-Strategy Approach Preserves Purity

| Property | Status | Explanation |
|----------|--------|-------------|
| Immutability | ✅ | Agent struct still immutable, new agents returned |
| Determinism | ✅ | Same `(agent, action)` always produces same result |
| No Side Effects | ✅ | All effects remain as directives |
| Referential Transparency | ✅ | `cmd/2` can be memoized |
| Composability | ✅ | Strategies compose as pure functions |

### The Key Insight

```elixir
# This is just function composition - pure by definition
def cmd(agent, instrs, ctx) do
  {a1, d1} = ChildA.cmd(agent, instrs, ctx)
  {a2, d2} = ChildB.cmd(a1, instrs, ctx)
  {a2, d1 ++ d2}
end
```

Child strategies are just pure functions. The meta-strategy orchestrates calls to these functions and merges results. No mutation, no side effects, no impurity introduced.

---

## Implementation Roadmap

### Phase 1: Foundation (1-2 days)

1. Create `Jido.Agent.Strategy.NestedState` helper module
2. Implement base `Jido.Agent.Strategy.Multi` with `:pipeline` mode
3. Add tests for pipeline composition

### Phase 2: Modes (1-2 days)

1. Add `:switch` mode with `active` tracking
2. Add `:fanout` mode with parallel-style semantics
3. Implement directive merge strategies
4. Add mode-specific tests

### Phase 3: Ergonomics (1 day)

1. Add `strategy_snapshot/1` support for composite state
2. Implement `signal_routes/1` delegation/merging
3. Add debugging/introspection helpers

### Phase 4: Documentation & Examples (1 day)

1. Update guides with multi-strategy patterns
2. Add example agents using Multi strategy
3. Document best practices for child strategy design

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| State shape divergence | Medium | Medium | Treat `__strategy__` as fully owned by top-level strategy; promote `snapshot/2` |
| Directive ordering confusion | Low | Low | Document clear merge rules; default to child declaration order |
| Complexity creep | Medium | Medium | Start minimal (pipeline + switch); resist graph/DSL over-engineering |
| Child strategy compatibility | Low | Medium | Provide adapter pattern for strategies that assume single ownership |

---

## Conclusion

The meta-strategy approach is the optimal path for multi-strategy support:

1. **Zero core API changes** - Existing code continues to work
2. **FP purity preserved** - `cmd/2` remains a pure function
3. **Maximum flexibility** - Pipeline, fanout, switch, nested all supported
4. **Incremental adoption** - Use when needed, ignore otherwise
5. **Clean abstraction** - Composition handled at the right layer

The key insight is that "multiple strategies" is a **strategy implementation concern**, not an agent-level concern. By keeping the agent-strategy interface clean (one strategy module) and pushing composition into meta-strategy modules, we get all the power with none of the complexity leakage.
