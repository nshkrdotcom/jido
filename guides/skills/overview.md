# Sensors and Skills

## Overview

Sensors and Skills are Jido's mechanisms for extending agent capabilities and integrating with external systems. Sensors provide event-based triggers and monitoring, while Skills package reusable functionality that can be dynamically loaded into agents.

### Core Principles

1. **Extensibility**

   - Modular skill packages
   - Pluggable sensor system
   - Dynamic loading

2. **Integration**

   - External system monitoring
   - Event-based triggers
   - Custom routing logic

3. **Reusability**
   - Composable skills
   - Shared behaviors
   - Configurable components

## Implementation

### Basic Sensor Structure

```elixir
defmodule MyApp.Sensors.SystemMonitor do
  use Jido.Sensor

  @type config :: %{
    interval: pos_integer(),
    threshold: float()
  }

  @impl true
  def init(opts) do
    state = %{
      interval: opts[:interval] || 5000,
      threshold: opts[:threshold] || 0.8,
      last_check: nil
    }

    schedule_next_check(state.interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:check, state) do
    {cpu, memory} = get_system_metrics()

    if cpu > state.threshold or memory > state.threshold do
      signal = build_alert_signal(cpu, memory)
      {:signal, signal, state}
    else
      {:ok, state}
    end
  end

  # Private Helpers

  defp schedule_next_check(interval) do
    Process.send_after(self(), :check, interval)
  end

  defp get_system_metrics do
    cpu = :cpu_sup.util()
    memory = :erlang.memory(:total) / :erlang.memory(:system)
    {cpu, memory}
  end

  defp build_alert_signal(cpu, memory) do
    Jido.Signal.new("system.resources.critical", %{
      cpu_usage: cpu,
      memory_usage: memory,
      timestamp: DateTime.utc_now()
    })
  end
end
```

### Cron-based Sensor

```elixir
defmodule MyApp.Sensors.ScheduledTask do
  use Jido.Sensor
  use Quantum, otp_app: :my_app

  @impl true
  def init(opts) do
    schedule = opts[:schedule] || "0 * * * *" # Every hour
    task = opts[:task] || &default_task/0

    Quantum.new_job()
    |> Quantum.schedule(schedule)
    |> Quantum.run(task)

    {:ok, %{schedule: schedule, task: task}}
  end

  @impl true
  def handle_job_complete(result, state) do
    signal = Jido.Signal.new("task.completed", %{
      result: result,
      timestamp: DateTime.utc_now()
    })

    {:signal, signal, state}
  end

  defp default_task do
    # Default implementation
    {:ok, :completed}
  end
end
```

### Skill Definition

```elixir
defmodule MyApp.Skills.Arithmetic do
  use Jido.Skill

  @type operation :: :add | :subtract | :multiply | :divide
  @type number_pair :: {number(), number()}

  @impl true
  def routes do
    [
      %{
        path: "math.operation",
        instruction: {__MODULE__, :handle_operation}
      }
    ]
  end

  @impl true
  def handle_signal(%{type: "math.operation"} = signal) do
    with {:ok, operation} <- extract_operation(signal.data),
         {:ok, numbers} <- extract_numbers(signal.data),
         {:ok, result} <- apply_operation(operation, numbers) do
      {:ok, build_result_signal(result)}
    end
  end

  # Operation Handlers

  def handle_operation(%{operation: :add, numbers: {a, b}}) do
    {:ok, a + b}
  end

  def handle_operation(%{operation: :subtract, numbers: {a, b}}) do
    {:ok, a - b}
  end

  def handle_operation(%{operation: :multiply, numbers: {a, b}}) do
    {:ok, a * b}
  end

  def handle_operation(%{operation: :divide, numbers: {_, 0}}) do
    {:error, :division_by_zero}
  end

  def handle_operation(%{operation: :divide, numbers: {a, b}}) do
    {:ok, a / b}
  end

  # Private Helpers

  defp extract_operation(%{operation: op}) when op in [:add, :subtract, :multiply, :divide] do
    {:ok, op}
  end
  defp extract_operation(_), do: {:error, :invalid_operation}

  defp extract_numbers(%{a: a, b: b}) when is_number(a) and is_number(b) do
    {:ok, {a, b}}
  end
  defp extract_numbers(_), do: {:error, :invalid_numbers}

  defp apply_operation(operation, numbers) do
    handle_operation(%{operation: operation, numbers: numbers})
  end

  defp build_result_signal(result) do
    Jido.Signal.new("math.result", %{
      result: result,
      timestamp: DateTime.utc_now()
    })
  end
end
```

### Dynamic Skill Loading

```elixir
defmodule MyApp.Agents.Calculator do
  use Jido.Agent

  @impl true
  def init(opts) do
    skills = [MyApp.Skills.Arithmetic]
    {:ok, %{}, skills: skills}
  end

  @impl true
  def handle_signal(%{type: "math." <> _} = signal, state) do
    # Signal will be routed to the Arithmetic skill
    {:ok, state}
  end
end
```

## Advanced Features

### Sensor Groups

```elixir
defmodule MyApp.Sensors.Group do
  use Jido.Sensor.Group

  @impl true
  def init(opts) do
    children = [
      {MyApp.Sensors.SystemMonitor, interval: 5000},
      {MyApp.Sensors.ScheduledTask, schedule: "*/15 * * * *"}
    ]

    {:ok, children}
  end

  @impl true
  def handle_child_signal(sensor, signal, state) do
    enriched_signal = enrich_signal(signal, sensor)
    {:signal, enriched_signal, state}
  end

  defp enrich_signal(signal, sensor) do
    Map.update!(signal, :metadata, fn metadata ->
      Map.put(metadata, :source_sensor, sensor)
    end)
  end
end
```

### Skill Composition

```elixir
defmodule MyApp.Skills.Advanced do
  use Jido.Skill

  @impl true
  def compose do
    [
      MyApp.Skills.Arithmetic,
      MyApp.Skills.Logging,
      MyApp.Skills.Metrics
    ]
  end

  @impl true
  def handle_signal(signal, composed_results) do
    # Process results from composed skills
    {:ok, merge_results(composed_results)}
  end
end
```

## Testing & Verification

### Sensor Tests

```elixir
defmodule MyApp.Sensors.SystemMonitorTest do
  use ExUnit.Case
  use Jido.Test.SensorCase

  alias MyApp.Sensors.SystemMonitor

  describe "system monitoring" do
    test "emits alert when threshold exceeded" do
      {:ok, pid} = start_supervised_sensor(SystemMonitor, threshold: 0.5)

      # Simulate high system load
      :sys.replace_state(pid, fn state ->
        %{state | threshold: 0.1}
      end)

      send(pid, :check)

      assert_receive {:signal, signal}
      assert signal.type == "system.resources.critical"
    end
  end
end
```

### Skill Tests

```elixir
defmodule MyApp.Skills.ArithmeticTest do
  use ExUnit.Case
  use Jido.Test.SkillCase

  alias MyApp.Skills.Arithmetic

  describe "handle_operation/1" do
    test "performs basic arithmetic" do
      assert {:ok, 5} = Arithmetic.handle_operation(%{
        operation: :add,
        numbers: {2, 3}
      })

      assert {:ok, 6} = Arithmetic.handle_operation(%{
        operation: :multiply,
        numbers: {2, 3}
      })
    end

    test "handles division by zero" do
      assert {:error, :division_by_zero} = Arithmetic.handle_operation(%{
        operation: :divide,
        numbers: {1, 0}
      })
    end
  end
end
```

## Production Readiness

### Configuration

```elixir
# config/runtime.exs
config :my_app, MyApp.Sensors,
  system_monitor: [
    interval: :timer.seconds(5),
    threshold: 0.8
  ],
  scheduled_task: [
    schedule: "*/15 * * * *",
    timeout: :timer.seconds(30)
  ]
```

### Monitoring

1. **Telemetry Events**

   ```elixir
   :telemetry.attach(
     "sensor-metrics",
     [:jido, :sensor, :emit],
     &MyApp.Metrics.handle_sensor_event/4,
     nil
   )
   ```

2. **Health Checks**
   ```elixir
   def health_check do
     sensors = MyApp.Sensors.Group.list_active()
     if length(sensors) > 0, do: :ok, else: {:error, :no_sensors}
   end
   ```

### Common Issues

1. **Resource Usage**

   - Monitor sensor CPU/memory usage
   - Adjust check intervals
   - Implement rate limiting

2. **Skill Loading**

   - Handle missing dependencies
   - Version compatibility
   - Memory leaks

3. **Integration**
   - External system availability
   - Network timeouts
   - Data format changes

## Best Practices

1. **Sensor Design**

   - Keep checks lightweight
   - Implement proper cleanup
   - Use appropriate intervals

2. **Skill Implementation**

   - Clear responsibility boundaries
   - Proper error handling
   - Efficient signal routing

3. **Testing**

   - Mock external systems
   - Test edge cases
   - Verify cleanup

4. **Production**
   - Monitor resource usage
   - Set appropriate timeouts
   - Implement circuit breakers

## Further Reading

- [Agent Documentation](../agents/overview.md)
- [Signal Routing](../signals/overview.md)
- [Advanced Patterns](../practices/advanced-patterns.md)
- [Error Handling](../practices/error-handling.md)
