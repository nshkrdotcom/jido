defmodule JidoTest.Agent.Runtime.PubSubTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Runtime.{PubSub, State, Signal}
  alias Jido.Signal, as: BaseSignal

  setup do
    test_pid = self()
    topic = "test.topic"
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})

    state = %State{
      agent: %{id: "test-agent"},
      pubsub: TestPubSub,
      topic: topic,
      status: :idle
    }

    {:ok, state: state, pubsub: TestPubSub, topic: topic, test_pid: test_pid}
  end

  describe "topic generation" do
    test "generates correct topic format" do
      topic = PubSub.generate_topic("test-123")
      assert topic == "jido.agent.test-123"
    end

    test "handles special characters in agent ID" do
      topic = PubSub.generate_topic("test/agent@123")
      assert topic == "jido.agent.test/agent@123"
    end
  end

  describe "event emission" do
    test "emits event with correct signal format", %{state: state} do
      :ok = PubSub.subscribe(state)
      event_type = Signal.transition_succeeded()
      payload = %{from: :idle, to: :running}

      :ok = PubSub.emit(state, event_type, payload)

      assert_receive %BaseSignal{
        type: ^event_type,
        source: "/agent/test-agent",
        data: ^payload
      }
    end

    test "includes correct metadata in emitted events", %{state: state} do
      :ok = PubSub.subscribe(state)
      event_type = Signal.transition_succeeded()
      :ok = PubSub.emit(state, event_type, %{from: :idle, to: :running})

      assert_receive %BaseSignal{data: %{from: :idle, to: :running}}
    end

    test "handles empty payload", %{state: state} do
      :ok = PubSub.subscribe(state)
      event_type = Signal.queue_cleared()
      :ok = PubSub.emit(state, event_type, %{})

      assert_receive %BaseSignal{
        type: ^event_type,
        data: %{}
      }
    end

    test "handles complex nested payloads", %{state: state} do
      :ok = PubSub.subscribe(state)
      event_type = Signal.process_started()

      payload = %{
        nested: %{
          array: [1, 2, 3],
          map: %{key: "value"}
        },
        list: ["a", "b", "c"]
      }

      :ok = PubSub.emit(state, event_type, payload)

      assert_receive %BaseSignal{
        type: ^event_type,
        data: ^payload
      }
    end
  end

  describe "subscription" do
    test "subscribes to topic successfully", %{state: state} do
      assert :ok = PubSub.subscribe(state)

      # Test subscription by emitting and receiving an event
      event_type = Signal.process_started()
      :ok = PubSub.emit(state, event_type, %{value: true})
      assert_receive %BaseSignal{type: ^event_type}
    end

    test "can subscribe multiple times to same topic", %{state: state} do
      assert :ok = PubSub.subscribe(state)
      assert :ok = PubSub.subscribe(state)
    end

    test "receives all events after subscribing", %{state: state} do
      assert :ok = PubSub.subscribe(state)

      event1 = Signal.process_started()
      event2 = Signal.process_terminated()
      event3 = Signal.transition_succeeded()

      :ok = PubSub.emit(state, event1, %{id: 1})
      :ok = PubSub.emit(state, event2, %{id: 2})
      :ok = PubSub.emit(state, event3, %{id: 3})

      assert_receive %BaseSignal{type: ^event1}
      assert_receive %BaseSignal{type: ^event2}
      assert_receive %BaseSignal{type: ^event3}
    end
  end

  describe "unsubscription" do
    test "unsubscribes from topic successfully", %{state: state} do
      :ok = PubSub.subscribe(state)
      assert :ok = PubSub.unsubscribe(state)

      # Should not receive events after unsubscribing
      event_type = Signal.process_started()
      :ok = PubSub.emit(state, event_type, %{value: true})
      refute_receive %BaseSignal{type: ^event_type}
    end

    test "can unsubscribe when not subscribed", %{state: state} do
      assert :ok = PubSub.unsubscribe(state)
    end

    test "stops receiving events after unsubscribe", %{state: state} do
      :ok = PubSub.subscribe(state)

      # Should receive event before unsubscribe
      before_event = Signal.process_started()
      :ok = PubSub.emit(state, before_event, %{})
      assert_receive %BaseSignal{type: ^before_event}

      :ok = PubSub.unsubscribe(state)

      # Should not receive event after unsubscribe
      after_event = Signal.process_terminated()
      :ok = PubSub.emit(state, after_event, %{})
      refute_receive %BaseSignal{type: ^after_event}
    end
  end
end
