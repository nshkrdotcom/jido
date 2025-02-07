defmodule Jido.Agent.Server.StateTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Server.State
  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Signal

  @moduletag :capture_log

  describe "new state" do
    test "creates state with required fields" do
      agent = BasicAgent.new("test")
      state = %State{agent: agent}

      assert state.agent == agent

      assert state.dispatch == [
               out: {:bus, [target: :default, stream: "agent"]},
               log: {:logger, []},
               err: {:console, []}
             ]

      assert state.status == :idle
      assert state.log_level == :info
      assert state.mode == :auto
      assert :queue.is_queue(state.pending_signals)
      assert :queue.is_empty(state.pending_signals)
    end

    test "creates state with custom output config" do
      agent = BasicAgent.new("test")
      dispatch = [pid: [target: self()]]
      state = %State{agent: agent, dispatch: dispatch}

      assert state.agent == agent
      assert state.dispatch == dispatch
      assert state.status == :idle
      assert state.log_level == :info
      assert state.mode == :auto
      assert :queue.is_queue(state.pending_signals)
      assert :queue.is_empty(state.pending_signals)
    end

    test "creates state with custom log_level and mode settings" do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, log_level: :debug, mode: :step}

      assert state.agent == agent
      assert state.log_level == :debug
      assert state.mode == :step
      assert state.status == :idle
      assert :queue.is_queue(state.pending_signals)
      assert :queue.is_empty(state.pending_signals)
    end
  end

  describe "transition/2" do
    setup do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, dispatch: [pid: [target: self()]]}
      {:ok, state: state}
    end

    test "allows valid transitions and emits signals", %{state: state} do
      # initializing -> idle
      state = %{state | status: :initializing}
      transition_succeeded = "jido.agent.event.transition.succeeded"
      assert {:ok, %State{status: :idle}} = State.transition(state, :idle)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :initializing, to: :idle}
                      }}

      # idle -> planning
      state = %{state | status: :idle}
      assert {:ok, %State{status: :planning}} = State.transition(state, :planning)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :idle, to: :planning}
                      }}

      # planning -> running
      state = %{state | status: :planning}
      assert {:ok, %State{status: :running}} = State.transition(state, :running)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :planning, to: :running}
                      }}

      # running -> paused
      state = %{state | status: :running}
      assert {:ok, %State{status: :paused}} = State.transition(state, :paused)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :running, to: :paused}
                      }}

      # paused -> running
      state = %{state | status: :paused}
      assert {:ok, %State{status: :running}} = State.transition(state, :running)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :paused, to: :running}
                      }}
    end

    test "rejects invalid transitions and emits failure signals", %{state: state} do
      # Can't go from idle to paused
      state = %{state | status: :idle}
      transition_failed = "jido.agent.event.transition.failed"
      assert {:error, {:invalid_transition, :idle, :paused}} = State.transition(state, :paused)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_failed,
                        data: %{from: :idle, to: :paused}
                      }}

      # Can't go from running to planning
      state = %{state | status: :running}

      assert {:error, {:invalid_transition, :running, :planning}} =
               State.transition(state, :planning)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_failed,
                        data: %{from: :running, to: :planning}
                      }}
    end
  end

  describe "enqueue/2" do
    setup do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, dispatch: [pid: [target: self()]]}
      {:ok, state: state}
    end

    test "successfully enqueues a signal", %{state: state} do
      signal = %Signal{type: "test.signal", source: "test", id: "test-1"}
      {:ok, new_state} = State.enqueue(state, signal)

      assert :queue.len(new_state.pending_signals) == 1
      {{:value, queued_signal}, _} = :queue.out(new_state.pending_signals)
      assert queued_signal == signal
    end

    test "returns error and emits overflow signal when queue is at max capacity", %{state: state} do
      state = %{state | max_queue_size: 1}
      signal1 = %Signal{type: "test.signal.1", source: "test", id: "test-1"}
      signal2 = %Signal{type: "test.signal.2", source: "test", id: "test-2"}
      queue_overflow = "jido.agent.event.queue.overflow"

      {:ok, state_with_one} = State.enqueue(state, signal1)
      assert :queue.len(state_with_one.pending_signals) == 1

      assert {:error, :queue_overflow} = State.enqueue(state_with_one, signal2)
      assert :queue.len(state_with_one.pending_signals) == 1

      assert_receive {:signal,
                      %Signal{
                        type: ^queue_overflow,
                        data: %{queue_size: 1, max_size: 1}
                      }}
    end
  end

  describe "dequeue/1" do
    setup do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, dispatch: [pid: [target: self()]]}
      {:ok, state: state}
    end

    test "successfully dequeues a signal", %{state: state} do
      signal = %Signal{type: "test.signal", source: "test", id: "test-1"}
      {:ok, state_with_signal} = State.enqueue(state, signal)

      assert {:ok, dequeued_signal, new_state} = State.dequeue(state_with_signal)
      assert dequeued_signal == signal
      assert :queue.is_empty(new_state.pending_signals)
    end

    test "returns empty queue when queue is empty", %{state: state} do
      assert {:error, :empty_queue} = State.dequeue(state)
    end

    test "maintains FIFO order when dequeuing multiple signals", %{state: state} do
      signal1 = %Signal{type: "test.signal.1", source: "test", id: "test-1"}
      signal2 = %Signal{type: "test.signal.2", source: "test", id: "test-2"}
      signal3 = %Signal{type: "test.signal.3", source: "test", id: "test-3"}

      {:ok, state} = State.enqueue(state, signal1)
      {:ok, state} = State.enqueue(state, signal2)
      {:ok, state} = State.enqueue(state, signal3)

      {:ok, dequeued1, state} = State.dequeue(state)
      {:ok, dequeued2, state} = State.dequeue(state)
      {:ok, dequeued3, _state} = State.dequeue(state)

      assert dequeued1 == signal1
      assert dequeued2 == signal2
      assert dequeued3 == signal3
    end
  end

  describe "clear_queue/1" do
    setup do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, dispatch: [pid: [target: self()]]}
      {:ok, state: state}
    end

    test "clears all signals from the queue and emits signal", %{state: state} do
      signal1 = %Signal{type: "test.signal.1", source: "test", id: "test-1"}
      signal2 = %Signal{type: "test.signal.2", source: "test", id: "test-2"}
      queue_cleared = "jido.agent.event.queue.cleared"

      {:ok, state} = State.enqueue(state, signal1)
      {:ok, state} = State.enqueue(state, signal2)
      assert :queue.len(state.pending_signals) == 2

      {:ok, cleared_state} = State.clear_queue(state)
      assert :queue.is_empty(cleared_state.pending_signals)
      assert_receive {:signal, %Signal{type: ^queue_cleared, data: %{queue_size: 2}}}
    end

    test "clearing an empty queue emits signal with zero size", %{state: state} do
      queue_cleared = "jido.agent.event.queue.cleared"
      assert :queue.is_empty(state.pending_signals)
      {:ok, cleared_state} = State.clear_queue(state)
      assert :queue.is_empty(cleared_state.pending_signals)
      assert_receive {:signal, %Signal{type: ^queue_cleared, data: %{queue_size: 0}}}
    end
  end

  describe "check_queue_size/1" do
    setup do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, dispatch: [pid: [target: self()]]}
      {:ok, state: state}
    end

    test "returns current queue size when within limits", %{state: state} do
      assert {:ok, 0} = State.check_queue_size(state)

      signal = %Signal{type: "test.signal", source: "test", id: "test-1"}
      {:ok, state_with_signal} = State.enqueue(state, signal)
      assert {:ok, 1} = State.check_queue_size(state_with_signal)
    end

    test "returns error when queue size exceeds maximum", %{state: state} do
      state = %{state | max_queue_size: 0}
      signal = %Signal{type: "test.signal", source: "test", id: "test-1"}

      # Since max_queue_size is 0, enqueue should fail immediately
      assert {:error, :queue_overflow} = State.enqueue(state, signal)
      queue_overflow = "jido.agent.event.queue.overflow"

      assert_receive {:signal,
                      %Signal{
                        type: ^queue_overflow,
                        data: %{queue_size: 0, max_size: 0}
                      }}
    end
  end

  describe "reply_refs management" do
    setup do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, dispatch: [pid: [target: self()]]}
      {:ok, state: state}
    end

    test "can store and retrieve reply refs", %{state: state} do
      signal_id = "test-signal-1"
      from = {self(), make_ref()}

      # Store reply ref
      state = State.store_reply_ref(state, signal_id, from)
      assert State.get_reply_ref(state, signal_id) == from

      # Remove reply ref
      state = State.remove_reply_ref(state, signal_id)
      assert State.get_reply_ref(state, signal_id) == nil
    end

    test "handles missing reply refs gracefully", %{state: state} do
      assert State.get_reply_ref(state, "nonexistent") == nil
      assert State.remove_reply_ref(state, "nonexistent") == state
    end
  end
end
