# Jido.Observe – Unified Agent Observability

## Summary

A minimal, unified observability façade for Jido agents using `:telemetry` and `Logger`. No OpenTelemetry dependency—that's for a future `jido_otel` package.

**Goals:**
- Centralize all agent observability (signals, actions, LLM calls, tools)
- Enable debugging during development
- Support production-level observability
- Power a Phoenix dashboard for agent run visualization
- Provide extension points for future tracing backends

---

## Module Structure

```
lib/jido/observe.ex                 # Main façade
lib/jido/observe/log.ex             # Threshold-based logging
lib/jido/observe/tracer.ex          # Behaviour for extension (OTel later)
lib/jido/observe/noop_tracer.ex     # Default no-op implementation
```

---

## API Design

### `Jido.Observe` – Main Façade

```elixir
defmodule Jido.Observe do
  @moduledoc """
  Unified observability for Jido agents.
  
  Wraps :telemetry events and Logger with a simple API.
  Extensible via the Tracer behaviour for future OTel integration.
  """
  
  @type event_prefix :: [atom()]
  @type metadata :: map()
  @type span_ctx :: %{
    event_prefix: event_prefix(),
    start_time: integer(),
    metadata: metadata(),
    tracer_ctx: term()
  }
  
  @doc "Wrap synchronous work with telemetry span"
  @spec with_span(event_prefix(), metadata(), (() -> result)) :: result when result: term()
  def with_span(event_prefix, metadata, fun)
  
  @doc "Start an async span (for Task-based work)"
  @spec start_span(event_prefix(), metadata()) :: span_ctx()
  def start_span(event_prefix, metadata)
  
  @doc "Finish span successfully"
  @spec finish_span(span_ctx(), map()) :: :ok
  def finish_span(span_ctx, extra_measurements \\ %{})
  
  @doc "Finish span with error"
  @spec finish_span_error(span_ctx(), atom(), term(), list()) :: :ok
  def finish_span_error(span_ctx, kind, reason, stacktrace)
  
  @doc "Conditional logging based on threshold"
  @spec log(Logger.level(), iodata(), keyword()) :: :ok
  def log(level, message, metadata \\ [])
end
```

### `Jido.Observe.Log` – Threshold Control

```elixir
defmodule Jido.Observe.Log do
  @moduledoc "Centralized log threshold for observability."
  
  def threshold do
    Application.get_env(:jido, :observability, [])
    |> Keyword.get(:log_level, :info)
  end
  
  def log(level, message, opts \\ []) do
    Jido.Util.cond_log(threshold(), level, message, opts)
  end
end
```

### `Jido.Observe.Tracer` – Extension Behaviour

```elixir
defmodule Jido.Observe.Tracer do
  @moduledoc """
  Behaviour for tracing backends.
  
  Implement this to integrate OpenTelemetry or other tracing systems.
  The default NoopTracer does nothing.
  """
  
  @callback span_start(event_prefix :: [atom()], metadata :: map()) :: term()
  @callback span_stop(tracer_ctx :: term(), measurements :: map()) :: :ok
  @callback span_exception(tracer_ctx :: term(), kind :: atom(), reason :: term(), stacktrace :: list()) :: :ok
end

defmodule Jido.Observe.NoopTracer do
  @behaviour Jido.Observe.Tracer
  
  def span_start(_prefix, _meta), do: nil
  def span_stop(_ctx, _measurements), do: :ok
  def span_exception(_ctx, _kind, _reason, _stack), do: :ok
end
```

---

## Telemetry Events

### Event Naming Convention

All events follow: `[:jido, :ai, <domain>, <operation>, <stage>]`

### Core Events

| Event | Description |
|-------|-------------|
| `[:jido, :ai, :react, :run, :start\|:stop\|:exception]` | ReAct run lifecycle |
| `[:jido, :ai, :react, :step, :start\|:stop\|:exception]` | Per-step within a run |
| `[:jido, :ai, :llm, :request, :start\|:stop\|:exception]` | LLM API calls |
| `[:jido, :ai, :tool, :invoke, :start\|:stop\|:exception]` | Tool executions |

### Standard Measurements

| Key | Type | Description |
|-----|------|-------------|
| `:system_time` | integer | Start timestamp (`:start` events) |
| `:duration` | integer | Nanoseconds (`:stop`/`:exception` events) |
| `:prompt_tokens` | integer | LLM input tokens |
| `:completion_tokens` | integer | LLM output tokens |
| `:total_tokens` | integer | Total tokens |

### Standard Metadata

**Always present:**
- `:agent_id` – Agent identifier
- `:strategy` – Strategy module (e.g., `Jido.AI.Strategy.ReAct`)

**Agent hierarchy (optional):**
- `:parent_agent_id` – Parent agent for nested agents
- `:root_agent_id` – Root of agent tree

**ReAct-specific:**
- `:react_run_id` – Unique run identifier
- `:step_number` – Current iteration
- `:max_steps` – Configured limit
- `:termination_reason` – `:final_answer | :max_iterations | :error`

**LLM-specific:**
- `:call_id` – LLM call identifier
- `:provider` – e.g., `:anthropic`, `:openai`
- `:model` – e.g., `"claude-sonnet-4-20250514"`
- `:temperature`, `:max_tokens`

**Tool-specific:**
- `:tool_call_id` – Tool call identifier
- `:tool_name` – Tool name string
- `:tool_module` – Action module

---

## Instrumentation Points

### 1. ReAct Strategy (`Jido.AI.Strategy.ReAct`)

**Location:** `process_instruction/2`

```elixir
defp process_instruction(agent, instruction) do
  state = StratState.get(agent, %{})
  react_run_id = state[:react_run_id] || Jido.Util.generate_id()
  step_number = machine.iteration + 1
  
  Jido.Observe.with_span([:jido, :ai, :react, :step], %{
    agent_id: agent.id,
    react_run_id: react_run_id,
    step_number: step_number,
    strategy: __MODULE__
  }, fn ->
    # ... existing logic
  end)
end
```

**Run lifecycle:** Emit `run:start` on first step, `run:stop` on completion.

### 2. LLM Directive (`Jido.AI.Directive.ReqLLMStream`)

**Location:** `DirectiveExec.exec/3`

```elixir
def exec(directive, _signal, state) do
  span_ctx = Jido.Observe.start_span([:jido, :ai, :llm, :request], %{
    call_id: directive.id,
    model: directive.model,
    provider: directive.provider,
    temperature: directive.temperature
  })
  
  Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
    try do
      result = stream_with_callbacks(...)
      Jido.Observe.finish_span(span_ctx, %{
        prompt_tokens: result.usage.prompt_tokens,
        completion_tokens: result.usage.completion_tokens
      })
      # send signal...
    rescue
      e ->
        Jido.Observe.finish_span_error(span_ctx, :error, e, __STACKTRACE__)
        # handle error...
    end
  end)
end
```

### 3. Tool Directive (`Jido.AI.Directive.ToolExec`)

**Location:** `DirectiveExec.exec/3`

```elixir
def exec(directive, _signal, state) do
  span_ctx = Jido.Observe.start_span([:jido, :ai, :tool, :invoke], %{
    tool_call_id: directive.id,
    tool_name: directive.tool_name,
    tool_module: directive.action_module
  })
  
  Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
    try do
      result = Jido.Exec.run(action_module, args, context)
      Jido.Observe.finish_span(span_ctx, %{})
      # send signal...
    rescue
      e ->
        Jido.Observe.finish_span_error(span_ctx, :error, e, __STACKTRACE__)
        # handle error...
    end
  end)
end
```

---

## Configuration

```elixir
# config/config.exs
config :jido, :observability,
  log_level: :info,           # :debug in dev for verbose output
  tracer: Jido.Observe.NoopTracer  # swap for OTel later

# Development
config :jido, :observability,
  log_level: :debug

# Production  
config :jido, :observability,
  log_level: :warning
```

---

## Phoenix Dashboard Support

A dashboard can subscribe to these events and build agent run trees:

```elixir
:telemetry.attach_many("agent-dashboard", [
  [:jido, :ai, :react, :run, :start],
  [:jido, :ai, :react, :run, :stop],
  [:jido, :ai, :react, :step, :stop],
  [:jido, :ai, :llm, :request, :stop],
  [:jido, :ai, :tool, :invoke, :stop]
], &Dashboard.handle_event/4, %{})
```

**Key capabilities:**
- Filter by `:agent_id` for single-agent view
- Build run timeline via `:react_run_id` + `:step_number`
- Show agent trees via `:parent_agent_id` / `:root_agent_id`
- Display LLM token usage and latency
- Track tool execution patterns

---

## Future: `jido_otel` Package

When distributed tracing is needed:

1. Implement `Jido.Observability.Tracer` with OpenTelemetry
2. Configure: `config :jido, :observability, tracer: JidoOtel.Tracer`
3. Add sanitization/redaction for prompts in span attributes
4. Export to Jaeger, Honeycomb, Langfuse, etc.

The core `Jido.Observability` API stays the same—only the tracer changes.

---

## Implementation Phases

### Phase 1: Core Module (2-3 hours)
- [ ] Create `Jido.Observe` with `with_span/3`, `start_span/2`, `finish_span/2`
- [ ] Create `Jido.Observe.Log` wrapper
- [ ] Create `Jido.Observe.Tracer` behaviour + `NoopTracer`
- [ ] Add configuration support

### Phase 2: Instrumentation (2-3 hours)
- [ ] Instrument ReAct strategy (run + step events)
- [ ] Instrument `ReqLLMStream` directive
- [ ] Instrument `ToolExec` directive
- [ ] Add debug logging at key points

### Phase 3: Testing & Docs (1-2 hours)
- [ ] Write tests for observability module
- [ ] Document telemetry events in moduledocs
- [ ] Add example telemetry handler for testing

---

## Design Decisions

1. **Single façade** – One module to learn, one place to configure
2. **Behaviour for extension** – Clean hook for future OTel without coupling
3. **Consistent metadata** – Same keys across all events for easy dashboard queries
4. **No dependencies** – Just `:telemetry` and `Logger` from stdlib
5. **Async-aware** – `start_span/finish_span` pattern for Task-based work
