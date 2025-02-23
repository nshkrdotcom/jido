defmodule Jido.Signal.Bus.StreamTest do
  use ExUnit.Case, async: true
  alias Jido.Signal.Bus.Stream
  alias Jido.Signal.Bus.BusState
  alias Jido.Signal.Bus.RecordedSignal
  alias Jido.Signal.Router
  alias Jido.Signal
  alias Jido.Signal.ID

  @moduletag :capture_log

  describe "publish/3" do
    test "rejects invalid signals" do
      state = %BusState{
        id: "test-bus",
        name: :test_bus,
        router: Router.new!(),
        log: []
      }

      signals = [
        %{value: 1},
        %{value: 2}
      ]

      assert {:error, :invalid_signals} = Stream.publish(state, signals)
    end

    test "successfully publishes valid signals to the bus" do
      state = %BusState{
        id: "test-bus",
        name: :test_bus,
        router: Router.new!(),
        log: []
      }

      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "/test",
          data: %{value: 2}
        })

      signals = [signal1, signal2]

      {:ok, recorded_signals, new_state} = Stream.publish(state, signals)

      assert length(recorded_signals) == 2
      assert length(new_state.log) == 2

      # Verify recorded signals have required fields and maintain their original types
      [recorded1, recorded2] = recorded_signals
      assert recorded1.type == "test.signal.1"
      assert recorded2.type == "test.signal.2"
      assert is_struct(recorded1.signal, Signal)
      assert is_struct(recorded2.signal, Signal)
    end

    test "maintains strict ordering of signals published in rapid succession" do
      state = %BusState{
        id: "test-bus",
        name: :test_bus,
        router: Router.new!(),
        log: []
      }

      # Create 10 signals as fast as possible
      signals =
        Enum.map(1..10, fn i ->
          {:ok, signal} =
            Signal.new(%{
              type: "test.signal.#{i}",
              source: "/test",
              data: %{value: i}
            })

          signal
        end)

      {:ok, recorded_signals, _new_state} = Stream.publish(state, signals)

      # Extract timestamps and sequence numbers
      signal_info =
        Enum.map(recorded_signals, fn signal ->
          timestamp = ID.extract_timestamp(signal.id)
          sequence = ID.sequence_number(signal.id)
          {signal.id, timestamp, sequence}
        end)

      # Group by timestamp to see if any were created in the same millisecond
      by_timestamp = Enum.group_by(signal_info, fn {_id, ts, _seq} -> ts end)

      # For each timestamp group, verify sequences are strictly increasing
      Enum.each(by_timestamp, fn {_ts, group} ->
        sequences = Enum.map(group, fn {_id, _ts, seq} -> seq end)
        assert sequences == Enum.sort(sequences)
      end)

      # Verify the original order is maintained
      original_types = Enum.map(signals, & &1.type)
      recorded_types = Enum.map(recorded_signals, & &1.type)
      assert recorded_types == original_types

      # Verify IDs are in chronological order
      ids = Enum.map(recorded_signals, & &1.id)
      [first | rest] = ids

      assert Enum.reduce_while(rest, first, fn id, prev ->
               case ID.compare(prev, id) do
                 # Order is correct, continue
                 :lt -> {:cont, id}
                 # Order violation found
                 _ -> {:halt, false}
               end
             end)
    end

    test "appends new signals to existing log" do
      {:ok, original_signal} =
        Signal.new(%{
          type: "test.signal.1",
          source: "/test",
          data: %{value: 0}
        })

      existing_signal = %RecordedSignal{
        id: "existing",
        correlation_id: nil,
        type: "test.signal.1",
        signal: original_signal,
        created_at: DateTime.utc_now()
      }

      state = %BusState{
        id: "test-bus",
        name: :test_bus,
        router: Router.new!(),
        log: [existing_signal]
      }

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal.2",
          source: "/test",
          data: %{value: 1}
        })

      signals = [signal]

      {:ok, recorded_signals, new_state} = Stream.publish(state, signals)

      assert length(recorded_signals) == 1
      assert length(new_state.log) == 2
      assert hd(new_state.log) == existing_signal
      assert hd(recorded_signals).type == "test.signal.2"
    end
  end

  describe "filter/4" do
    test "filters signals by type" do
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "/test",
          data: %{value: 2}
        })

      signals = [
        %RecordedSignal{
          id: "1",
          correlation_id: nil,
          type: "test.signal.1",
          signal: signal1,
          created_at: DateTime.utc_now()
        },
        %RecordedSignal{
          id: "2",
          correlation_id: nil,
          type: "test.signal.2",
          signal: signal2,
          created_at: DateTime.utc_now()
        }
      ]

      state = %BusState{
        id: "test-bus",
        name: :test_bus,
        router: Router.new!(),
        log: signals
      }

      {:ok, filtered_signals} = Stream.filter(state, "test.signal.1")
      assert length(filtered_signals) == 1
      assert hd(filtered_signals).id == "1"
    end

    test "returns all signals with wildcard type pattern" do
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "/test",
          data: %{value: 2}
        })

      signals = [
        %RecordedSignal{
          id: "1",
          correlation_id: nil,
          type: "test.signal.1",
          signal: signal1,
          created_at: DateTime.utc_now()
        },
        %RecordedSignal{
          id: "2",
          correlation_id: nil,
          type: "test.signal.2",
          signal: signal2,
          created_at: DateTime.utc_now()
        }
      ]

      state = %BusState{
        id: "test-bus",
        name: :test_bus,
        router: Router.new!(),
        log: signals
      }

      {:ok, filtered_signals} = Stream.filter(state, "*")
      assert length(filtered_signals) == 2
    end

    test "respects start_timestamp and batch_size" do
      {:ok, base_signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 0}
        })

      # Create signals with increasing timestamps
      now = DateTime.utc_now()

      signals =
        Enum.map(1..5, fn i ->
          signal = %{base_signal | data: %{value: i}}
          timestamp = DateTime.add(now, i * 1000, :millisecond)

          %RecordedSignal{
            id: "#{i}",
            correlation_id: nil,
            type: "test.signal",
            signal: signal,
            created_at: timestamp
          }
        end)

      state = %BusState{
        id: "test-bus",
        name: :test_bus,
        router: Router.new!(),
        log: signals
      }

      # Get timestamp from signal "2" and filter from there
      signal_2 = Enum.find(signals, &(&1.id == "2"))
      start_ts = DateTime.to_unix(signal_2.created_at, :millisecond)

      {:ok, filtered_signals} = Stream.filter(state, "test.signal", start_ts, batch_size: 2)
      assert length(filtered_signals) == 2
      assert Enum.map(filtered_signals, & &1.id) == ["3", "4"]
    end
  end
end
