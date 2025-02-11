# Signal Bus

## Introduction

The Signal Bus serves as the communication backbone of Jido's agent system, providing a flexible and extensible infrastructure for signal routing and persistence. By default, Jido provides two bus implementations:

- `PubSub` - A lightweight, in-memory pub/sub system for development and testing
- `InMemory` - A more feature-complete in-memory implementation supporting persistence and replay

The Signal Bus is designed as a primary extension point for building production agent systems, allowing you to implement custom adapters for your specific persistence and scaling needs.

## Core Concepts

### Signal Flow

The Signal Bus manages the flow of signals through your agent system:

1. Agents publish signals to named streams
2. The bus routes signals to subscribers
3. Subscribers process signals and acknowledge receipt
4. The bus maintains signal ordering and tracking

### Bus Capabilities

Different bus implementations can provide varying levels of functionality:

- **Basic Pub/Sub** - Simple signal routing without persistence
- **Persistence** - Storage and replay of signal streams
- **Snapshots** - Point-in-time state capture
- **Ordering** - Guaranteed signal ordering within streams
- **Acknowledgments** - Tracking of signal processing status

## Using the Built-in Buses

### PubSub Bus

The `PubSub` adapter provides lightweight pub/sub messaging using Phoenix.PubSub:

```elixir
# Configuration
config :my_app, MyApp.Bus,
  adapter: Jido.Bus.Adapters.PubSub

# Usage
{:ok, bus} = Jido.Bus.start_link(name: MyApp.Bus)

# Subscribe to a stream
:ok = Jido.Bus.subscribe(MyApp.Bus, "agent-123")

# Publish signals
signal = %Jido.Signal{
  type: "agent.state.updated",
  source: "agent-123",
  data: %{status: "active"}
}
:ok = Jido.Bus.publish(MyApp.Bus, "agent-123", :any_version, [signal])
```

### InMemory Bus

The `InMemory` adapter adds persistence, replay, and snapshot capabilities:

```elixir
# Configuration
config :my_app, MyApp.Bus,
  adapter: Jido.Bus.Adapters.InMemory

# Usage
{:ok, bus} = Jido.Bus.start_link(name: MyApp.Bus)

# Create persistent subscription
{:ok, subscription} = Jido.Bus.subscribe_persistent(
  MyApp.Bus,
  "agent-123",
  "subscriber-1",
  self(),
  :origin,
  []
)

# Replay stream from start
signals = Jido.Bus.replay(MyApp.Bus, "agent-123") |> Enum.to_list()

# Record snapshot
snapshot = %Jido.Bus.Snapshot{
  source_id: "agent-123",
  source_version: 42,
  data: current_state
}
:ok = Jido.Bus.record_snapshot(MyApp.Bus, snapshot)
```

## Creating Custom Bus Adapters

The Signal Bus is designed for extensibility through custom adapters. Common use cases include:

- Integration with event stores (EventStoreDB, Apache Kafka)
- Cloud service backends (AWS Kinesis, Google PubSub)
- Database-backed persistence (PostgreSQL, MongoDB)

### Implementing a Custom Adapter

Custom adapters implement the `Jido.Bus.Adapter` behaviour:

```elixir
defmodule MyApp.CustomBusAdapter do
  @behaviour Jido.Bus.Adapter

  @impl true
  def child_spec(application, config) do
    # Return child specs for your adapter
  end

  @impl true
  def publish(bus, stream_id, expected_version, signals, opts) do
    # Implement signal publishing
  end

  @impl true
  def replay(bus, stream_id, start_version \\ 0, read_batch_size \\ 1_000) do
    # Implement stream replay
  end

  @impl true
  def subscribe(bus, stream_id) do
    # Implement transient subscriptions
  end

  @impl true
  def subscribe_persistent(bus, stream_id, subscription_name, subscriber, start_from, opts) do
    # Implement persistent subscriptions
  end

  # Additional callback implementations...
end
```

### Key Design Considerations

When implementing a custom bus adapter:

1. **Consistency** - Ensure reliable signal delivery and ordering
2. **Performance** - Optimize for your system's throughput requirements
3. **Scalability** - Consider distributed deployment scenarios
4. **Monitoring** - Implement proper telemetry and logging
5. **Recovery** - Handle network partitions and node failures

## Production Recommendations

For production deployments:

1. **Choose the Right Backend**

   - Consider throughput requirements
   - Evaluate persistence needs
   - Plan for scaling

2. **Implement Proper Monitoring**

   - Track signal latency
   - Monitor queue depths
   - Set up alerts

3. **Plan for Recovery**

   - Implement snapshot strategies
   - Define replay policies
   - Test failure scenarios

4. **Scale Appropriately**
   - Use persistent subscriptions for load balancing
   - Implement partitioning if needed
   - Monitor resource usage

## See Also

- [Signal Overview](signals/overview.md)
- [Signal Routing](signals/routing.md)
- [Signal Serialization](signals/serialization.md)
