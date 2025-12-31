# Jido.Debug Tool Specification

## Overview

This document specifies structured tools for debugging Jido agents. The implementation is extensible to support programmatic debugging interfaces.

## Design Principles

1. **Structured Data** - All APIs return structured data (maps/structs), not strings
2. **Consistent Schemas** - Predictable field names and types across all tools
3. **Composable** - Tools can be chained together for complex workflows
4. **Observable** - All debug operations emit telemetry events
5. **Safe** - Read-only operations by default, mutations require explicit confirmation

---

## Tool: `get_agent_status`

Returns the current status of an agent instance.

### Input Schema

```elixir
%{
  agent_id: String.t(),        # Required: Agent instance ID
  include_raw_state: boolean() # Optional: Include full state (default: false)
}
```

### Output Schema

```elixir
%{
  agent_module: String.t(),      # e.g., "MyApp.ChatAgent"
  agent_id: String.t(),          # e.g., "019b74ab-..."
  pid: String.t(),               # e.g., "#PID<0.123.0>"
  
  # Strategy snapshot
  snapshot: %{
    status: :idle | :running | :waiting | :success | :failure,
    done?: boolean(),
    result: term() | nil,
    details: %{
      # Strategy-specific fields, e.g.:
      iteration: integer(),
      phase: atom(),
      streaming_text: String.t()
    }
  },
  
  # Optional (when include_raw_state: true)
  raw_state: map()
}
```

### Example Usage

```elixir
# LLM calls tool
tool_call(%{
  name: "get_agent_status",
  arguments: %{
    agent_id: "019b74ab-9d75-707c-a37e-de2f70840b10",
    include_raw_state: false
  }
})

# Returns
%{
  agent_module: "DebugCounterAgent",
  agent_id: "019b74ab-9d75-707c-a37e-de2f70840b10",
  pid: "#PID<0.234.0>",
  snapshot: %{
    status: :idle,
    done?: false,
    result: nil,
    details: %{counter: 5, target: 10}
  }
}
```

---

## Tool: `get_agent_trace`

Returns the execution trace for an agent (when debug events enabled).

### Input Schema

```elixir
%{
  agent_id: String.t(),     # Required: Agent instance ID
  limit: integer(),         # Optional: Max events to return (default: 100)
  since_timestamp: String.t() # Optional: ISO8601 timestamp filter
}
```

### Output Schema

```elixir
%{
  agent_id: String.t(),
  trace_available: boolean(),    # False if tracing disabled
  buffer_size: integer(),        # Total events in buffer
  events: [
    %{
      event: [atom()],            # e.g., [:jido, :agent, :status, :changed]
      timestamp: String.t(),      # ISO8601
      measurements: map(),
      metadata: map()
    }
  ]
}
```

### Example Usage

```elixir
# LLM calls tool
tool_call(%{
  name: "get_agent_trace",
  arguments: %{
    agent_id: "019b74ab-9d75-707c-a37e-de2f70840b10",
    limit: 10
  }
})

# Returns
%{
  agent_id: "019b74ab-9d75-707c-a37e-de2f70840b10",
  trace_available: true,
  buffer_size: 25,
  events: [
    %{
      event: [:jido, :agent, :status, :changed],
      timestamp: "2025-12-31T15:30:45.123Z",
      measurements: %{},
      metadata: %{
        agent_id: "019b74ab-...",
        old_counter: 4,
        new_counter: 5,
        action: :increment
      }
    }
    # ... more events
  ]
}
```

---

## Tool: `list_agents`

Returns all running agent instances in the system.

### Input Schema

```elixir
%{
  status_filter: atom() | nil,  # Optional: Filter by status (:running, :success, etc.)
  module_filter: String.t() | nil # Optional: Filter by agent module name
}
```

### Output Schema

```elixir
%{
  count: integer(),
  agents: [
    %{
      agent_id: String.t(),
      agent_module: String.t(),
      pid: String.t(),
      status: atom(),
      done?: boolean()
    }
  ]
}
```

### Example Usage

```elixir
# LLM calls tool
tool_call(%{
  name: "list_agents",
  arguments: %{
    status_filter: :running
  }
})

# Returns
%{
  count: 2,
  agents: [
    %{
      agent_id: "019b74ab-...",
      agent_module: "ChatAgent",
      pid: "#PID<0.234.0>",
      status: :running,
      done?: false
    },
    %{
      agent_id: "019b74ab-...",
      agent_module: "WeatherAgent",
      pid: "#PID<0.456.0>",
      status: :running,
      done?: false
    }
  ]
}
```

---

## Tool: `explain_agent_state`

Human-readable explanation of current agent state (uses existing status API).

### Input Schema

```elixir
%{
  agent_id: String.t(),
  verbosity: :brief | :detailed # Optional (default: :detailed)
}
```

### Output Schema

```elixir
%{
  agent_id: String.t(),
  summary: String.t(),          # Human-readable summary
  status_breakdown: %{
    current_status: atom(),
    is_terminal: boolean(),
    progress_indicator: String.t() | nil,  # e.g., "Iteration 3/10"
    waiting_for: String.t() | nil          # e.g., "Tool response"
  },
  recent_activity: [String.t()],  # Last N events as readable descriptions
  recommendations: [String.t()]   # Suggested next steps for debugging
}
```

### Example Usage

```elixir
# LLM calls tool
tool_call(%{
  name: "explain_agent_state",
  arguments: %{
    agent_id: "019b74ab-9d75-707c-a37e-de2f70840b10",
    verbosity: :detailed
  }
})

# Returns
%{
  agent_id: "019b74ab-9d75-707c-a37e-de2f70840b10",
  summary: "DebugCounterAgent is idle with counter at 5 out of 10",
  status_breakdown: %{
    current_status: :idle,
    is_terminal: false,
    progress_indicator: "Counter: 5/10",
    waiting_for: nil
  },
  recent_activity: [
    "Incremented counter from 4 to 5",
    "Incremented counter from 3 to 4",
    "Decremented counter from 4 to 3"
  ],
  recommendations: [
    "Agent is idle - send 'counter.increment' signal to continue",
    "Agent will complete when counter reaches 10"
  ]
}
```

---

## Implementation Notes

### Extensibility Points

1. **Tool Registry** - Define tools in a registry for dynamic discovery
2. **Schema Validation** - Use Zoi/ExJsonSchema for input/output validation
3. **Access Control** - Hook for authorization (which agents can be debugged)
4. **Rate Limiting** - Prevent abuse of debug tools in production
5. **Audit Logging** - Track all debug tool invocations

### Example Tool Definition

```elixir
defmodule Jido.Debug.Tools.GetAgentStatus do
  @moduledoc "Tool for getting agent status"
  
  use Jido.Action,
    name: "get_agent_status",
    description: "Get the current status of a Jido agent instance",
    schema: [
      agent_id: [type: :string, required: true],
      include_raw_state: [type: :boolean, default: false]
    ]
  
  @impl true
  def run(params, _context) do
    with {:ok, pid} <- resolve_agent(params.agent_id),
         {:ok, status} <- AgentServer.status(pid) do
      result = %{
        agent_module: to_string(status.agent_module),
        agent_id: status.agent_id,
        pid: inspect(status.pid),
        snapshot: serialize_snapshot(status.snapshot)
      }
      
      result = if params.include_raw_state do
        Map.put(result, :raw_state, status.raw_state)
      else
        result
      end
      
      {:ok, result}
    end
  end
  
  defp serialize_snapshot(%Snapshot{} = s) do
    %{
      status: s.status,
      done?: s.done?,
      result: s.result,
      details: s.details
    }
  end
end
```

### Future Enhancements

1. **Streaming Updates** - Tool that yields status changes as they happen
2. **Interactive Stepping** - Tools for `next/1`, `continue/1` in step mode
3. **Trace Visualization** - Generate Mermaid diagrams from trace data
4. **Comparative Analysis** - Compare traces from multiple agent runs
5. **Anomaly Detection** - Flag unusual patterns in agent behavior

---

## Security Considerations

1. **Sensitive Data Redaction** - Automatic redaction respects `:redact_sensitive` config
2. **Agent Isolation** - Tools can only access agents in same node/cluster
3. **Read-Only Default** - Mutation tools (like sending signals) require explicit opt-in
4. **Audit Trail** - All tool invocations logged via telemetry
5. **Resource Limits** - Trace queries limited to prevent memory exhaustion
