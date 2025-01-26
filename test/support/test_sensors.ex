defmodule JidoTest.TestSensors do
  defmodule TestSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "test_sensor",
      description: "A sensor for testing",
      category: :test,
      tags: [:test, :unit],
      vsn: "1.0.0",
      schema: [
        test_param: [type: :integer, default: 0]
      ]

    @impl true
    def mount(opts) do
      state = %{
        id: Map.get(opts, :id, "test_id"),
        target: Map.get(opts, :target, "test_target"),
        sensor: Map.get(opts, :sensor, %{test_param: 42}),
        last_values: :queue.new(),
        config: Map.get(opts, :config, %{test_param: 42})
      }

      OK.success(state)
    end

    @impl true
    def deliver_signal(state) do
      {:ok,
       Jido.Signal.new(%{
         source: "#{state.sensor.name}:#{state.id}",
         subject: "test_signal",
         type: "test_signal",
         data: %{value: state.config.test_param},
         timestamp: DateTime.utc_now()
       })}
    end

    @impl true
    def on_before_deliver({:ok, signal}, state) do
      on_before_deliver(signal, state)
    end

    def on_before_deliver(%Jido.Signal{data: %{value: value}} = signal, _state) do
      if value == 42 do
        {:error, :invalid_value}
      else
        {:ok, signal}
      end
    end

    def on_before_deliver(signal, _state), do: {:ok, signal}

    @impl true
    def handle_info({:sensor_signal, signal}, state) do
      new_queue = :queue.in(signal, state.last_values)

      new_queue =
        if :queue.len(new_queue) > state.retain_last do
          {_, q} = :queue.out(new_queue)
          q
        else
          new_queue
        end

      new_state = %{state | last_values: new_queue}
      {:noreply, new_state}
    end

    @impl true
    def get_config do
      state = %{
        id: "test_id",
        target: "test_target",
        sensor: %{test_param: 42},
        last_values: :queue.new(),
        config: %{test_param: 42}
      }

      {:ok, state}
    end

    @impl true
    def set_config(config) do
      state = %{
        id: "test_id",
        target: "test_target",
        sensor: %{test_param: 42},
        last_values: :queue.new(),
        config: config
      }

      {:ok, state}
    end

    def get_last_values(pid) do
      state = :sys.get_state(pid)
      :queue.to_list(state.last_values)
    end
  end

  defmodule CounterSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "counter_sensor",
      description: "A sensor that emits a counter value at a specified interval",
      category: :counter,
      tags: [:counter, :interval],
      vsn: "1.0.0",
      schema: [
        floor: [type: :integer, default: 0],
        emit_interval: [type: :pos_integer, required: true]
      ]

    @impl true
    def mount(opts) do
      state = %{
        id: Map.get(opts, :id, "counter_id"),
        target: Map.get(opts, :target, "counter_target"),
        sensor: Map.get(opts, :sensor, %{floor: 0}),
        last_values: :queue.new(),
        config: Map.merge(%{floor: 0}, Map.get(opts, :config, %{})),
        counter: Map.get(opts, :floor, 0)
      }

      schedule_emit(state)
      OK.success(state)
    end

    @impl true
    def deliver_signal(state) do
      new_counter = state.counter + 1

      {:ok,
       Jido.Signal.new(%{
         source: "#{state.sensor.name}:#{state.id}",
         subject: "counter",
         type: "counter",
         data: %{value: new_counter},
         timestamp: DateTime.utc_now()
       })}
    end

    @impl true
    def get_config do
      {:ok, %{floor: 0}}
    end

    @impl true
    def set_config(config) do
      {:ok, config}
    end

    def handle_info(:emit, state) do
      case deliver_signal(state) do
        {:ok, signal} ->
          case Jido.Sensor.SignalDelivery.deliver({signal, %{target: state.target}}) do
            :ok ->
              schedule_emit(state)
              {:noreply, %{state | counter: state.counter + 1}}

            {:error, reason} ->
              Logger.warning("Error publishing signal: #{inspect(reason)}")
              schedule_emit(state)
              {:noreply, state}
          end
      end
    end

    defp schedule_emit(state) do
      Process.send_after(self(), :emit, state.config.emit_interval)
    end
  end

  defmodule ErrorSensor1 do
    use Jido.Sensor,
      name: "error_sensor",
      description: "A sensor that generates errors",
      category: :test,
      tags: [:test, :error]

    @impl true
    def mount(opts) do
      state = %{
        id: Map.get(opts, :id, "error_id"),
        target: Map.get(opts, :target, "error_target"),
        sensor: Map.get(opts, :sensor, %{error: true}),
        last_values: :queue.new(),
        config: Map.get(opts, :config, %{error: true})
      }

      OK.success(state)
    end

    @impl true
    def deliver_signal(_state) do
      Logger.warning("Test error in generate_signal")
      {:error, :test_error}
    end

    @impl true
    def get_config do
      state = %{
        id: "error_id",
        target: "error_target",
        sensor: %{error: true},
        last_values: :queue.new(),
        config: %{error: true}
      }

      {:ok, state}
    end

    @impl true
    def set_config(config) do
      state = %{
        id: "error_id",
        target: "error_target",
        sensor: %{error: true},
        last_values: :queue.new(),
        config: config
      }

      {:ok, state}
    end
  end

  defmodule ErrorSensor2 do
    use Jido.Sensor,
      name: "error_sensor",
      description: "A sensor that generates errors",
      category: :test,
      tags: [:test, :error]

    @impl true
    def mount(opts) do
      state = %{
        id: Map.get(opts, :id, "error_id"),
        target: Map.get(opts, :target, "error_target"),
        sensor: Map.get(opts, :sensor, %{error: true}),
        last_values: :queue.new(),
        config: Map.get(opts, :config, %{error: true})
      }

      OK.success(state)
    end

    @impl true
    def deliver_signal(state) do
      {:ok,
       Jido.Signal.new(%{
         source: "#{state.sensor.name}:#{state.id}",
         subject: "test_signal",
         type: "test_signal",
         data: %{value: 42},
         timestamp: DateTime.utc_now()
       })}
    end

    @impl true
    def on_before_deliver({:ok, signal}, state) do
      on_before_deliver(signal, state)
    end

    def on_before_deliver(%Jido.Signal{} = _signal, _state) do
      Logger.warning("Test error in before_publish")
      {:error, :test_error}
    end

    def on_before_deliver(signal, _state), do: {:ok, signal}

    @impl true
    def get_config do
      state = %{
        id: "error_id",
        target: "error_target",
        sensor: %{error: true},
        last_values: :queue.new(),
        config: %{error: true}
      }

      {:ok, state}
    end

    @impl true
    def set_config(config) do
      state = %{
        id: "error_id",
        target: "error_target",
        sensor: %{error: true},
        last_values: :queue.new(),
        config: config
      }

      {:ok, state}
    end
  end
end
