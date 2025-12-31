# Jido.Observe Production Critique

## Executive Summary

The `Jido.Observe` implementation is a **clean, idiomatic first cut** suitable for moderate production traffic. However, several changes are recommended before deploying to high-throughput or APM-heavy environments:

1. **Tighten performance hotspots** (env lookups, `cond_log/4`)
2. **Harden error-handling** around tracer callbacks
3. **Decide on the OpenTelemetry/DataDog integration story**

The overall design aligns well with Telemetry best practices, but it's missing production features like sampling, context propagation, and log/trace correlation.

**Effort Estimate:**
- Simple-path improvements: S–M (1–4 hours)
- Full "APM-first" redesign with OTel/DataDog: L–XL

---

## 1. Production Readiness & Performance

### Current Behavior Per Span

Each span performs:
- `System.monotonic_time()` + `System.system_time()` at start
- One `:telemetry.execute/3` at start and stop/exception
- 1–3 `Application.get_env/3` calls (via `tracer/0` and `Log.threshold/0`)
- Map allocation for `span_ctx` containing full `metadata`
- On error: stacktrace merged into metadata (potentially large)

### Findings

| Concern | Severity | Notes |
|---------|----------|-------|
| `Application.get_env/3` per span | Low-Medium | ETS read is cheap but not free at high QPS |
| `Logger.levels()` called per log | Low | Unnecessary allocation in `cond_log/4` |
| Large metadata retention | Medium | Full prompts/responses increase GC pressure |
| Stacktrace in error metadata | Low | Can be large; copied into telemetry events |
| Duration unit documentation | Low | Docs say "nanoseconds" but uses `:native` time units |

### Recommendations

#### 1.1 Fix Duration Unit Documentation (S)

```elixir
# Option A: Update docs to say "native time units"
# Option B: Explicitly use nanoseconds
start_time = System.monotonic_time(:nanosecond)
start_system_time = System.system_time(:nanosecond)
```

#### 1.2 Precompute Logger Levels in `cond_log/4` (S)

```elixir
# In Jido.Util
@valid_levels Logger.levels()

def cond_log(threshold_level, message_level, message, opts \\ []) do
  cond do
    threshold_level not in @valid_levels or message_level not in @valid_levels ->
      :ok
    Logger.compare_levels(threshold_level, message_level) in [:lt, :eq] ->
      Logger.log(message_level, message, opts)
    true ->
      :ok
  end
end
```

#### 1.3 Cache Observability Config (M, deferrable)

For very high QPS, use compile-time config:

```elixir
# In Jido.Observe
@observability Application.compile_env(:jido, :observability, [])
@default_tracer Jido.Observe.NoopTracer

defp tracer do
  Keyword.get(@observability, :tracer, @default_tracer)
end

# In Jido.Observe.Log
@observability Application.compile_env(:jido, :observability, [])
@default_level :info

def threshold do
  Keyword.get(@observability, :log_level, @default_level)
end
```

> **Note:** Only do this if config is truly static. Keep `get_env/3` if runtime configurability is needed.

#### 1.4 Guard `finish_span/2` Against Non-Map Inputs (S)

```elixir
def finish_span(%{...} = span_ctx, extra_measurements) 
    when is_map(extra_measurements) do
  # ...
end
```

#### 1.5 Document Metadata Best Practices (S)

Add to moduledoc:

> **Metadata should be small, identifying data** (IDs, step numbers, model names), not full prompts/responses. For large payloads, include derived measurements (`prompt_tokens`, `prompt_size_bytes`) rather than the raw content.

---

## 2. DataDog/APM Integration Intrusiveness

### Current Integration Options

The design provides **two** integration paths:

1. **Telemetry handlers**: Attach to `[:jido, :ai, ...]` events and translate to spans
2. **Tracer behaviour**: Implement `Jido.Observe.Tracer` and wire to OTel/DataDog SDK

### Intrusiveness Assessment

| Aspect | Assessment |
|--------|------------|
| Swapping tracer | **Low intrusion** - single config change |
| Callsite changes | **None required** |
| Telemetry integration | **Standard** - follows community patterns |
| OTel integration | **Straightforward** - behaviour is minimal |

### Missing for Full APM

- No explicit parent/context propagation API
- No hook for cross-process/HTTP context injection/extraction
- No carrier concept for distributed tracing

### Recommendations

#### 2.1 Document Integration Paths (S)

Add to `Jido.Observe` moduledoc:

```markdown
## APM Integration

For **OpenTelemetry/DataDog/Honeycomb**:

- **Option A**: Attach telemetry handlers to `[:jido, :ai, ...]` events 
  and construct spans there
- **Option B**: Implement `Jido.Observe.Tracer` and use `:opentelemetry_api` 
  internally

The `Tracer` behaviour is optional and not the only integration hook.
```

#### 2.2 Provide Example OTel Tracer (M)

```elixir
defmodule Jido.Observe.OtelTracer do
  @moduledoc """
  Example OpenTelemetry tracer implementation.
  
  Requires `opentelemetry_api` dependency.
  """
  @behaviour Jido.Observe.Tracer
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def span_start(event_prefix, metadata) do
    span_name = Enum.join(event_prefix, ".")
    Tracer.start_span(span_name, attributes: Map.to_list(metadata))
  end

  @impl true
  def span_stop(ctx, measurements) do
    Tracer.set_attributes(Map.to_list(measurements))
    Tracer.end_span(ctx)
  end

  @impl true
  def span_exception(ctx, kind, reason, stacktrace) do
    Tracer.record_exception(ctx, reason, stacktrace)
    Tracer.set_status(ctx, OpenTelemetry.status(:error, inspect(reason)))
    Tracer.end_span(ctx)
  end
end
```

#### 2.3 Keep Tracer Minimal

Do **not** add baggage/carrier APIs to the behaviour yet. Those belong in the OTel tracer implementation or telemetry handlers, not in Jido's core.

---

## 3. Architecture Concerns

### 3.1 Why is `cond_log/4` Still in `Jido.Util`?

**Assessment:** This is **correct**.

- `cond_log/4` is a general logging utility, not conceptually tied to observability
- `Jido.Observe.Log.log/3` is a thin, observability-scoped façade around it
- This layering is appropriate

**Recommendation:** 
- Mark `cond_log/4` as `@doc false` if you want to discourage direct use
- Point users to `Jido.Observe.log/3` instead

### 3.2 Tracer Lookup via `Application.get_env/3`

**Assessment:** Acceptable for most workloads.

- Called 2–3 times per span (start, stop/exception)
- ETS read is cheap but measurable at very high QPS

**Recommendation:** Use `Application.compile_env/3` only if profiling shows this as a hotspot. Do **not** use `:persistent_term` unless you need runtime updates.

### 3.3 No Span Context Propagation for Distributed Tracing

**Assessment:** This is **not Jido's job** (yet).

Within BEAM:
- Context propagates via `span_ctx` map passed to Tasks

For distributed tracing:
- OTel/DataDog tracer uses current process context as parent
- Cross-service propagation (HTTP, queues) handled by application/framework integrations

**Recommendation:**
- Document that Jido spans nest inside whatever parent span is current
- Cross-service propagation is expected to be handled externally
- Add `inject/2`, `extract/2` callbacks later if Jido initiates outbound HTTP

---

## 4. Telemetry Best Practices Alignment

### Findings

| Aspect | Status |
|--------|--------|
| Event naming (`[:prefix, :start\|:stop\|:exception]`) | ✅ Correct |
| Manual spans vs `:telemetry.span/3` | ✅ OK (consistent) |
| `System.monotonic_time()` for duration | ✅ Recommended |
| Measurements structure | ✅ Standard |

**Minor deviation:** Telemetry docs often recommend including both `start_time` and `duration`, but your pattern is still reasonable.

### Recommendations

#### 4.1 Consider Helper Macros for Common Prefixes (S)

```elixir
def with_llm_span(metadata, fun),
  do: with_span([:jido, :ai, :llm, :request], metadata, fun)

def with_tool_span(metadata, fun),
  do: with_span([:jido, :ai, :tool, :invoke], metadata, fun)
```

Reduces accidental divergence in event naming.

#### 4.2 Document Handler Usage (S)

Add example of attaching a telemetry handler:

```elixir
:telemetry.attach(
  "jido-llm-metrics",
  [:jido, :ai, :llm, :request, :stop],
  fn _event, measurements, metadata, _config ->
    # Record to StatsD, Prometheus, etc.
  end,
  nil
)
```

---

## 5. Error Handling Robustness

### Current Behavior

`with_span/3`:
- Wraps in `try ... rescue ... catch`
- On `rescue e` → `finish_span_error` then `reraise`
- On `catch kind, reason` → `finish_span_error` then `:erlang.raise`

This **correctly preserves error semantics**.

### Critical Issue

**If the tracer implementation raises, it crashes user code.**

This is dangerous with third-party tracer implementations (DataDog, OTel SDKs).

### Recommendation: Isolate Tracer Failures (M – Important)

```elixir
def start_span(event_prefix, metadata) do
  start_time = System.monotonic_time()
  start_system_time = System.system_time()

  :telemetry.execute(...)

  tracer_ctx =
    try do
      tracer().span_start(event_prefix, metadata)
    rescue
      e ->
        Logger.error("Jido tracer span_start/2 failed: #{inspect(e)}")
        nil
    end

  %{... tracer_ctx: tracer_ctx}
end

def finish_span(%{tracer_ctx: tracer_ctx} = span_ctx, extra_measurements)
    when is_map(extra_measurements) do
  # ... telemetry.execute ...
  
  try do
    tracer().span_stop(tracer_ctx, measurements)
  rescue
    e ->
      Logger.error("Jido tracer span_stop/2 failed: #{inspect(e)}")
  end
  
  :ok
end

def finish_span_error(%{tracer_ctx: tracer_ctx} = span_ctx, kind, reason, stacktrace) do
  # ... telemetry.execute ...
  
  try do
    tracer().span_exception(tracer_ctx, kind, reason, stacktrace)
  rescue
    e ->
      Logger.error("Jido tracer span_exception/4 failed: #{inspect(e)}")
  end
  
  :ok
end
```

**Observability should never crash the application.**

---

## 6. Missing Production Features

| Feature | Effort | Priority | Notes |
|---------|--------|----------|-------|
| Sampling | M–L | Medium | Sample by type; 100% errors, 1% successes |
| Trace/log correlation | M | High | Set `trace_id`/`span_id` in Logger metadata |
| Context propagation | L | Low | For distributed tracing across services |
| Span links | L | Low | For complex fan-out/fan-in workflows |
| Structured logging | S–M | Medium | JSON/logfmt formatters for log aggregators |
| PII filtering | M | Varies | Systematic scrubbing for compliance |

### Trace/Log Correlation Example

In tracer implementation:
```elixir
def span_start(event_prefix, metadata) do
  ctx = Tracer.start_span(...)
  Logger.metadata(trace_id: get_trace_id(ctx), span_id: get_span_id(ctx))
  ctx
end
```

This enables log-to-trace linking in DataDog/Honeycomb.

---

## 7. Code Quality Assessment

### Strengths ✅

- Clear moduledocs with examples
- Type specs for key types
- Error handling preserves original stacktrace
- `Tracer` behaviour is minimal and easy to implement
- Clean façade pattern for logging

### Areas to Improve

#### 7.1 Use Struct for `span_ctx` (M)

```elixir
defmodule Jido.Observe.SpanCtx do
  @moduledoc false
  @enforce_keys [:event_prefix, :start_time, :start_system_time, :metadata, :tracer_ctx]
  defstruct @enforce_keys
  
  @type t :: %__MODULE__{
    event_prefix: [atom()],
    start_time: integer(),
    start_system_time: integer(),
    metadata: map(),
    tracer_ctx: term()
  }
end
```

Benefits:
- Less fragile pattern matches
- Better Dialyzer info
- Forward-compatible field evolution

#### 7.2 Strengthen Guards and Specs (S)

```elixir
@spec finish_span(SpanCtx.t(), measurements()) :: :ok
def finish_span(%SpanCtx{} = span_ctx, extra_measurements \\ %{})
    when is_map(extra_measurements) do
  # ...
end
```

#### 7.3 Add Test Support Module (S)

```elixir
# test/support/test_tracer.ex
defmodule JidoTest.Support.TestTracer do
  @behaviour Jido.Observe.Tracer
  use Agent

  def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)
  
  def get_spans, do: Agent.get(__MODULE__, & &1)
  def clear, do: Agent.update(__MODULE__, fn _ -> [] end)

  @impl true
  def span_start(event_prefix, metadata) do
    ref = make_ref()
    Agent.update(__MODULE__, &[{:start, ref, event_prefix, metadata} | &1])
    ref
  end

  @impl true
  def span_stop(ref, measurements) do
    Agent.update(__MODULE__, &[{:stop, ref, measurements} | &1])
    :ok
  end

  @impl true
  def span_exception(ref, kind, reason, stacktrace) do
    Agent.update(__MODULE__, &[{:exception, ref, kind, reason, stacktrace} | &1])
    :ok
  end
end
```

---

## 8. Priority Action Items

### Immediate (Before Production)

1. **Isolate tracer failures** with try/rescue wrappers
2. **Add guards** for `extra_measurements` map
3. **Fix duration unit documentation** (native vs nanoseconds)

### Short-term (1–2 weeks)

4. **Precompute `Logger.levels()`** in `cond_log/4`
5. **Document integration paths** for DataDog/OTel
6. **Add test tracer** for better testing

### Medium-term (as needed)

7. **Convert `span_ctx` to struct**
8. **Add trace/log correlation** hooks
9. **Consider sampling** for high-volume spans
10. **Cache config** with `compile_env` if profiled as hotspot

---

## 9. When to Consider Advanced Path

Consider a more complex design if:

- **QPS ≥ tens of thousands spans/sec** and instrumentation shows in CPU profiles
- You need **end-to-end distributed traces** across many services with strict SLOs
- You want **rich dashboards/correlations** in DataDog/Honeycomb
- You have **security/compliance needs** around PII in metadata

For now, the current design plus simple-path improvements is a **solid, maintainable base** for production use.
