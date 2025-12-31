# Jido Agent Debugging Strategy

## Executive Summary

Extend the existing `Jido.Observe` infrastructure to provide developer-focused debugging utilities that require **zero source code changes** between environments. Control debug behavior via configuration files, environment variables, or runtime options.

### Core Principles

1. **Zero source code changes** - Agent modules identical in dev and prod
2. **Config-driven** - Control via config files, env vars, or runtime opts
3. **Build on existing patterns** - Extend `Jido.Observe` telemetry infrastructure
4. **Stable API surface** - Replace `agent.state.__strategy__` with clean `AgentServer.status/1`
5. **Developer ergonomics** - Step through iterations, visualize flows, trace execution

---

## Problem Statement

### Current Pain Points

**1. Manual state spelunking is brittle**
```elixir
# react_agent.exs (current approach)
case AgentServer.state(pid) do
  {:ok, %{agent: %{state: %{__strategy__: %{status: :error}}}}} -> ...
end
```
- Tightly coupled to `__strategy__` implementation details
- Breaks when strategy structure changes
- Unclear what fields are available

**2. No standard debugging workflow**
- Developers build custom polling loops for status
- Timeout scenarios dump raw state maps
- No trace/replay capability
- Can't step through ReAct iterations

**3. Agent complexity is opaque**
- Messages, processes, LLM calls flowing around
- Hard to visualize what's happening
- No clear "debugging entry point"

---

## Solution Architecture

### Leverage Existing Infrastructure

Jido already has `Jido.Observe` for telemetry. Extend it for debugging:
- Same event emission mechanism
- Add debug-specific event types
- Control verbosity via existing config patterns

---

## Implementation Plan

### Phase 1: Stable Status API (Foundation)

**Goal:** Provide clean, documented API for querying agent status - eliminate `__strategy__` spelunking.

#### Relationship to Existing `Strategy.Snapshot`

**Jido already has `Jido.Agent.Strategy.Snapshot`:**
```elixir
# Called via: Agent.strategy_snapshot(agent)
%Jido.Agent.Strategy.Snapshot{
  status: :idle | :running | :waiting | :success | :failure,
  done?: boolean(),
  result: term() | nil,
  details: %{
    # Strategy-specific metadata
    phase: :thinking,
    iteration: 2,
    streaming_text: "..."
  }
}
```

**Problem:** This is an agent-level API, not accessible from `AgentServer` (the GenServer).
- Requires passing the full `Agent` struct
- Example code uses `AgentServer.state/1` then digs into `agent.state.__strategy__`
- No direct way to query from PID

#### Solution: Add `AgentServer.status/1`

Wrap the existing snapshot with runtime/process information:

```elixir
defmodule Jido.AgentServer.Status do
  @moduledoc """
  Runtime status for an agent process.
  
  Combines `Strategy.Snapshot` with process-level metadata.
  """
  
  defstruct [
    :agent_module,      # MyAgent
    :agent_id,          # "abc-123"
    :pid,               # #PID<0.123.0>
    :snapshot,          # %Strategy.Snapshot{} - the core status
    :raw_state          # Escape hatch (full agent state)
  ]
  
  # Convenience delegates to snapshot
  def status(%__MODULE__{snapshot: s}), do: s.status
  def done?(%__MODULE__{snapshot: s}), do: s.done?
  def result(%__MODULE__{snapshot: s}), do: s.result
  def details(%__MODULE__{snapshot: s}), do: s.details
end

# Implementation in AgentServer
def status(server) do
  case state(server) do
    {:ok, %State{agent: agent}} ->
      snapshot = agent.__struct__.strategy_snapshot(agent)
      {:ok, %AgentServer.Status{
        agent_module: agent.__struct__,
        agent_id: agent.id,
        pid: self(),
        snapshot: snapshot,
        raw_state: agent.state
      }}
    {:error, _} = err -> err
  end
end

# Usage in react_agent.exs (cleaner)
case AgentServer.status(pid) do
  {:ok, %Status{snapshot: %{status: :success, result: answer}}} ->
    {:done, answer}
  {:ok, %Status{snapshot: %{status: :failure}}} ->
    {:error, "Agent failed"}
  {:ok, status} ->
    {:continue, status}
end
```

**Benefits:**
- **Reuses existing `Strategy.Snapshot`** - not duplicative
- Adds process-level metadata (PID, module, ID)
- Works from GenServer PID (no need for full agent struct)
- `raw_state` escape hatch for edge cases
- Delegates pattern match to snapshot fields

#### Add `AgentServer.stream_status/2`

Wrap the common polling pattern:

```elixir
# Instead of manual Stream.repeatedly + polling
AgentServer.stream_status(pid, interval_ms: 30)
|> Enum.reduce_while(acc, fn status, acc ->
  case status do
    %Status{status: :completed} -> {:halt, {:done, status}}
    %Status{status: :failed} -> {:halt, {:error, status}}
    status -> handle_streaming(status, acc)
  end
end)
```

---

### Phase 2: Enhanced Debug Events (Extend Jido.Observe)

**Goal:** Emit debug-level telemetry events for agent internals - controlled by config, zero code changes.

#### Configuration Approach

**Agent code never changes:**
```elixir
defmodule MyAgent do
  use Jido.Agent
  # Debug events automatically emitted based on config
end
```

**Control via config files** (config/dev.exs vs config/prod.exs):
```elixir
# config/dev.exs
config :jido, :observability,
  log_level: :debug,              # Existing
  tracer: Jido.Observe.NoopTracer, # Existing
  # NEW debug-specific options:
  debug_events: :all,             # :all | :minimal | :off
  redact_prompts: false,          # Show full prompts in dev
  trace_buffer_size: 1000         # Keep last N events per agent

# config/prod.exs  
config :jido, :observability,
  log_level: :warning,
  tracer: Jido.Observe.NoopTracer,
  debug_events: :off,             # No debug noise
  redact_prompts: true,           # Safety first
  trace_buffer_size: 0            # No buffering
```

**Override via env vars:**
```bash
JIDO_DEBUG_EVENTS=all JIDO_DEBUG_REDACT=false mix run my_agent.exs
```

**Override per-agent at runtime:**
```elixir
{:ok, pid} = AgentServer.start(
  agent: MyAgent,
  debug: [events: :all, redact_prompts: false]
)
```

#### New Debug Events

Extend `Jido.Observe` event vocabulary for agent-specific events:

```elixir
# Existing observability events (keep these):
[:jido, :ai, :react, :step, :start]
[:jido, :ai, :react, :step, :stop]
[:jido, :ai, :llm, :request, :start]
[:jido, :ai, :llm, :request, :stop]
[:jido, :ai, :tool, :invoke, :start]
[:jido, :ai, :tool, :invoke, :stop]

# NEW debug events (only when debug_events != :off):
[:jido, :agent, :iteration, :start]   # ReAct iteration boundary
[:jido, :agent, :iteration, :stop]    # With status, streaming_text
[:jido, :agent, :tool, :queued]       # Tool call added to pending
[:jido, :agent, :tool, :completed]    # Tool result available
[:jido, :agent, :status, :changed]    # :running -> :awaiting_tool, etc
```

**Metadata best practices:**
- Use existing `Jido.Observe` patterns (small identifying data)
- Add `redact_if_prod/2` helper for sensitive fields
- Emit measurements (token counts, durations) instead of content

```elixir
# Example event emission
Jido.Observe.with_span(
  [:jido, :agent, :iteration, :stop],
  %{
    agent_id: agent.id,
    iteration: 3,
    status: :awaiting_tool,
    streaming_text: redact_if_prod(text, opts),
    pending_tool_count: length(pending_tools)
  },
  fn -> :ok end
)
```

---

### Phase 3: Execution Tracing

**Goal:** Provide post-mortem debugging via execution traces.

#### Add `AgentServer.trace/1`

Return the complete execution trace as a list of telemetry events:

```elixir
# Get full trace for debugging timeouts/errors
{:ok, trace} = AgentServer.trace(pid)

# Each event in trace:
%{
  event: [:jido, :agent, :iteration, :stop],
  timestamp: ~U[2025-12-31 10:30:45.123Z],
  measurements: %{duration: 1_234_567},
  metadata: %{agent_id: "abc", iteration: 2, status: :awaiting_tool}
}
```

**Implementation:**
- Attach a `:telemetry` handler per agent that buffers events
- Ring buffer size controlled by `:trace_buffer_size` config
- Events automatically trimmed when buffer full
- Zero overhead when `trace_buffer_size: 0` (prod default)

**Usage example** (improved timeout handling in react_agent.exs):

```elixir
# Old approach
{:timeout, state} ->
  IO.puts("\n\n[TIMEOUT] Last state: #{inspect(state, pretty: true)}")

# New approach  
{:timeout, _state} ->
  {:ok, trace} = AgentServer.trace(pid)
  IO.puts("\n\n[TIMEOUT] Execution trace:")
  for event <- trace do
    IO.puts("#{format_timestamp(event.timestamp)} #{inspect(event.event)} - #{inspect(event.metadata)}")
  end
```

---

### Phase 4: Interactive Debugging (Future)

**Goal:** Step through agent execution in IEx.

#### Step Mode

```elixir
# Start agent in step mode
{:ok, pid} = AgentServer.start(
  agent: MyAgent,
  mode: :step  # Pause between ReAct iterations
)

Agent.ask(pid, "What's the weather?")

# In IEx:
iex> Jido.Debug.next(pid)
[ITERATION 1] Thinking... (streaming)
"I need to check the weather. Let me use the WeatherTool."

iex> Jido.Debug.next(pid)
[TOOL CALL] WeatherTool with args: %{location: "Algonquin, IL"}

iex> Jido.Debug.next(pid)
[ITERATION 2] Thinking... (streaming)
"Based on the weather data, it's currently 45°F and cloudy."

iex> Jido.Debug.continue(pid)
[COMPLETED] "It's currently 45°F and cloudy in Algonquin, IL."
```

**Implementation:**
- Agent pauses between iterations waiting for `:continue` message
- `Jido.Debug.next/1` sends single `:continue`
- `Jido.Debug.continue/1` switches to auto mode
- Natural yield points at iteration boundaries (no complex BEAM tracing)

#### Conditional Breakpoints

```elixir
{:ok, pid} = AgentServer.start(
  agent: MyAgent,
  debug: [break_on: [:tool_call, :error]]
)

# Runs normally until tool call, then enters step mode
Agent.ask(pid, query)
# [BREAK] Tool call detected - entering step mode
# Use Jido.Debug.next/1 to continue
```

---

### Phase 5: Visualization (Future)

#### Trace Export

```elixir
{:ok, trace} = AgentServer.trace(pid)
{:ok, mermaid} = Jido.Debug.to_mermaid(trace)
File.write!("agent_run.md", "```mermaid\n#{mermaid}\n```")
```

**Output:** Mermaid sequence diagram showing:
- Iterations as swimlanes
- Tool calls as interactions
- LLM requests/responses
- Final result

#### Mix Tasks

```bash
# Export trace from running agent
mix jido.debug.export <agent_id> --format=mermaid

# Record full session for replay
mix jido.debug.record <agent_id> --output=trace.json

# Replay with fake LLM (deterministic debugging)
mix jido.debug.replay trace.json --fake-llm
```

---

## Benefits and Trade-offs

### ✅ Advantages

**1. Zero source code changes**
- Agent modules identical across dev/test/prod
- No `use Jido.Debug` lines to add/remove
- No conditional compilation in agent code

**2. Builds on existing Jido.Observe**
- Consistent telemetry patterns
- Reuses config system
- Leverages existing `:telemetry` infrastructure

**3. Stable API surface**
- `AgentServer.status/1` won't break with strategy refactors
- Clear contract via struct definition
- `raw_state` escape hatch for edge cases

**4. Elixir-native debugging**
- Step mode works at natural boundaries (ReAct iterations)
- Trace leverages `:telemetry` not custom event system
- Fits mental model of debugging processes/GenServers

**5. Safety by default**
- Debug events off in prod (`:debug_events: :off`)
- Automatic prompt redaction (`redact_prompts: true`)
- Zero trace buffer in prod (`trace_buffer_size: 0`)

### ⚠️ Trade-offs

**1. Telemetry overhead**
- Even with no handlers, `:telemetry.execute/3` has small cost
- **Mitigation:** Only emit debug events when `debug_events != :off`

**2. Memory for trace buffers**
- Ring buffer per agent when tracing enabled
- **Mitigation:** Configurable size, defaults to 0 in prod

**3. Potential PII leakage**
- Debug events might capture sensitive prompts/data
- **Mitigation:** Auto-redaction in prod, clear security guidance in docs

**4. Debugging async work is still hard**
- Tool calls in Tasks/child processes
- **Mitigation:** Ensure all tool invocations emit events with correlation IDs

---

## Implementation Priority

### Must Have (Phase 1 & 2)
1. `AgentServer.status/1` - eliminates `__strategy__` coupling
2. `AgentServer.stream_status/2` - cleaner polling API
3. Debug event config system - zero code changes
4. Basic debug events - iteration start/stop, tool queue/complete

### Should Have (Phase 3)
5. `AgentServer.trace/1` - post-mortem debugging
6. Trace buffer implementation
7. Updated react_agent.exs example

### Nice to Have (Phase 4 & 5)
8. Step mode for IEx debugging
9. Conditional breakpoints
10. Mermaid export
11. Mix tasks for debug workflows

---

## Success Criteria

**For developers:**
- Can debug agent execution without reading Jido source code
- No code changes needed between dev and prod
- Clear mental model: "agent is a GenServer with iterations and tools"

**For Jido:**
- `__strategy__` becomes internal-only (no external usage)
- Example code shows clean patterns (no manual state polling)
- Foundation for future observability (OpenTelemetry, dashboards)
