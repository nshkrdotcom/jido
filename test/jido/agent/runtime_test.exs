defmodule Jido.Agent.RuntimeTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Signal
  alias Jido.Agent.Runtime
  alias JidoTest.TestAgents.SimpleAgent

  setup do
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    # {:ok, _} = start_supervised({Registry, keys: :unique, name: Jido.AgentRegistry})
    agent = SimpleAgent.new("test_agent")
    %{agent: agent}
  end

  describe "start_link/1" do
    test "starts worker with valid agent and pubsub", %{agent: agent} do
      {:ok, pid} = Runtime.start_link(agent: agent, pubsub: TestPubSub)
      assert Process.alive?(pid)
      assert [{^pid, nil}] = Registry.lookup(Jido.AgentRegistry, "test_agent")
    end

    test "starts worker with module agent", %{agent: _agent} do
      {:ok, pid} = Runtime.start_link(agent: SimpleAgent, pubsub: TestPubSub)
      assert Process.alive?(pid)
      state = :sys.get_state(pid)
      assert state.agent.__struct__ == SimpleAgent
    end

    test "starts worker with custom topic", %{agent: agent} do
      {:ok, pid} = Runtime.start_link(agent: agent, pubsub: TestPubSub, topic: "custom.topic")
      state = :sys.get_state(pid)
      assert state.topic == "custom.topic"
    end

    test "starts worker with custom name", %{agent: agent} do
      {:ok, pid} = Runtime.start_link(agent: agent, pubsub: TestPubSub, name: "custom_name")
      assert [{^pid, nil}] = Registry.lookup(Jido.AgentRegistry, "custom_name")
    end

    test "fails to start with missing pubsub", %{agent: agent} do
      assert_raise KeyError, ~r/key :pubsub not found/, fn ->
        Runtime.start_link(agent: agent)
      end
    end

    test "fails with duplicate registration", %{agent: agent} do
      {:ok, _pid1} = Runtime.start_link(agent: agent, pubsub: TestPubSub)

      assert {:error, {:already_started, _}} =
               Runtime.start_link(agent: agent, pubsub: TestPubSub)
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec", %{agent: agent} do
      spec = Runtime.child_spec(agent: agent, pubsub: TestPubSub)
      assert spec.id == Runtime
      assert spec.start == {Runtime, :start_link, [[agent: agent, pubsub: TestPubSub]]}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end

    test "allows custom id", %{agent: agent} do
      spec = Runtime.child_spec(agent: agent, pubsub: TestPubSub, id: :custom_id)
      assert spec.id == :custom_id
    end
  end

  describe "act/3" do
    setup %{agent: agent} do
      {:ok, pid} = Runtime.start_link(agent: agent, pubsub: TestPubSub)
      %{worker: pid}
    end

    test "synchronously executes action and returns new state", %{worker: pid} do
      {:ok, new_state} = Runtime.act(pid, :move, %{destination: :kitchen})
      assert new_state.agent.state.location == :kitchen
      # Verify actual state matches returned state
      assert :sys.get_state(pid).agent.state.location == :kitchen
    end

    test "handles invalid action parameters synchronously", %{worker: pid} do
      # Missing destination for move command
      assert {:error, %Jido.Error{type: :validation_error}} = Runtime.act(pid, :move, %{})
      state = :sys.get_state(pid)
      # Location shouldn't change
      assert state.agent.state.location == :home
    end

    test "queues synchronous actions when paused", %{worker: pid} do
      # First put the worker in paused state
      {:ok, _} = Runtime.manage(pid, :resume)
      {:ok, _} = Runtime.manage(pid, :pause)

      {:ok, state} = Runtime.act(pid, :move, %{destination: :kitchen})
      assert state.status == :paused
      assert :queue.len(state.pending) == 1

      # Resume and verify action is processed
      {:ok, running_state} = Runtime.manage(pid, :resume)
      assert running_state.agent.state.location == :kitchen
    end

    test "handles synchronous concurrent actions", %{worker: pid} do
      tasks =
        for dest <- [:kitchen, :living_room, :bedroom] do
          Task.async(fn -> Runtime.act(pid, :move, %{destination: dest}) end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Last action should win
      state = :sys.get_state(pid)
      assert state.agent.state.location in [:kitchen, :living_room, :bedroom]
    end
  end

  describe "act_async/3" do
    setup %{agent: agent} do
      {:ok, pid} = Runtime.start_link(agent: agent, pubsub: TestPubSub)
      %{worker: pid}
    end

    test "asynchronously executes action", %{worker: pid} do
      assert :ok = Runtime.act_async(pid, :move, %{destination: :kitchen})
      # Wait a bit for async processing
      :timer.sleep(100)
      state = :sys.get_state(pid)
      assert state.agent.state.location == :kitchen
    end

    test "handles invalid action parameters asynchronously", %{worker: pid} do
      # Missing destination
      assert :ok = Runtime.act_async(pid, :move, %{})
      :timer.sleep(100)
      state = :sys.get_state(pid)
      # Location shouldn't change
      assert state.agent.state.location == :home
    end

    test "queues asynchronous actions when paused", %{worker: pid} do
      # First put the worker in paused state
      {:ok, _} = Runtime.manage(pid, :resume)
      {:ok, _} = Runtime.manage(pid, :pause)

      assert :ok = Runtime.act_async(pid, :move, %{destination: :kitchen})
      state = :sys.get_state(pid)
      assert state.status == :paused
      assert :queue.len(state.pending) == 1
    end

    test "handles asynchronous concurrent actions", %{worker: pid} do
      tasks =
        for dest <- [:kitchen, :living_room, :bedroom] do
          Task.async(fn -> Runtime.act_async(pid, :move, %{destination: dest}) end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))

      # Wait for processing
      :timer.sleep(100)
      # Last action should win
      state = :sys.get_state(pid)
      assert state.agent.state.location in [:kitchen, :living_room, :bedroom]
    end
  end

  describe "manage/3" do
    setup %{agent: agent} do
      {:ok, pid} = Runtime.start_link(agent: agent, pubsub: TestPubSub)
      %{worker: pid}
    end

    test "pauses worker", %{worker: pid} do
      {:ok, running_state} = Runtime.manage(pid, :resume)
      assert running_state.status == :running

      {:ok, state} = Runtime.manage(pid, :pause)
      assert state.status == :paused
    end

    test "resumes worker", %{worker: pid} do
      {:ok, running_state} = Runtime.manage(pid, :resume)
      assert running_state.status == :running

      {:ok, paused_state} = Runtime.manage(pid, :pause)
      assert paused_state.status == :paused

      {:ok, state} = Runtime.manage(pid, :resume)
      assert state.status == :running
    end

    test "handles invalid state transitions", %{worker: pid} do
      # Try to pause when already idle
      {:error, {:invalid_state, :idle}} = Runtime.manage(pid, :pause)

      # Try to resume when already running
      {:ok, _} = Runtime.manage(pid, :resume)
      {:error, {:invalid_state, :running}} = Runtime.manage(pid, :resume)
    end

    test "resets worker", %{worker: pid} do
      # Queue some commands
      Runtime.act(pid, %{command: :move, destination: :kitchen})
      Runtime.act(pid, %{command: :move, destination: :living_room})

      {:ok, state} = Runtime.manage(pid, :reset)
      assert state.status == :idle
      assert :queue.len(state.pending) == 0
    end

    test "handles state transitions during pending commands", %{worker: pid} do
      # Queue commands while paused
      {:ok, _} = Runtime.manage(pid, :resume)
      {:ok, _} = Runtime.manage(pid, :pause)

      Runtime.act(pid, :move, %{destination: :kitchen})
      Runtime.act(pid, :move, %{destination: :living_room})

      {:ok, state} = Runtime.manage(pid, :resume)
      assert state.status == :running

      # Wait for commands to process
      :timer.sleep(100)
      final_state = :sys.get_state(pid)
      assert final_state.agent.state.location == :living_room
    end

    test "returns error for invalid command", %{worker: pid} do
      assert {:error, :invalid_command} = Runtime.manage(pid, :invalid_command)
    end
  end

  describe "pubsub and events" do
    setup %{agent: agent} do
      topic = "test.topic"
      {:ok, pid} = Runtime.start_link(agent: agent, pubsub: TestPubSub, topic: topic)
      Phoenix.PubSub.subscribe(TestPubSub, topic)
      %{worker: pid, topic: topic}
    end

    test "emits events for state transitions", %{worker: pid} do
      {:ok, _} = Runtime.manage(pid, :resume)
      assert_receive %Signal{type: "jido.agent.state_changed", data: %{from: :idle, to: :running}}

      {:ok, _} = Runtime.manage(pid, :pause)

      assert_receive %Signal{
        type: "jido.agent.state_changed",
        data: %{from: :running, to: :paused}
      }
    end

    test "emits events for completed actions", %{worker: pid} do
      Runtime.act(pid, :move, %{destination: :kitchen})
      assert_receive %Signal{type: "jido.agent.act_completed"}, 1000
    end

    test "handles malformed signals", %{worker: pid, topic: topic} do
      # Send malformed signal directly
      Phoenix.PubSub.broadcast(TestPubSub, topic, %{invalid: "signal"})

      # Runtime should still be alive and functioning
      assert Process.alive?(pid)
      assert :ok = Runtime.act_async(pid, :move, %{destination: :kitchen})
    end

    test "returns configured topic", %{worker: pid, topic: topic} do
      assert {:ok, ^topic} = Runtime.get_topic(pid)
    end
  end

  describe "max queue size" do
    setup %{agent: agent} do
      max_queue_size = 2
      topic = "test.topic"

      {:ok, pid} =
        Runtime.start_link(
          agent: agent,
          pubsub: TestPubSub,
          topic: topic,
          max_queue_size: max_queue_size
        )

      Phoenix.PubSub.subscribe(TestPubSub, topic)

      # First resume to get to running state, then pause to force command queueing
      {:ok, _} = Runtime.manage(pid, :resume)
      {:ok, _} = Runtime.manage(pid, :pause)

      %{worker: pid, max_queue_size: max_queue_size}
    end

    test "accepts commands up to max queue size", %{worker: pid, max_queue_size: max_size} do
      # Fill queue to capacity
      for i <- 1..max_size do
        assert :ok = Runtime.act_async(pid, :move, %{destination: "loc_#{i}"})
      end

      # Verify no overflow events were emitted
      refute_receive %Signal{type: "jido.agent.queue_overflow"}
    end

    test "drops commands when queue is full", %{worker: pid, max_queue_size: max_size} do
      # Fill queue to capacity
      for i <- 1..max_size do
        assert :ok = Runtime.act_async(pid, :move, %{destination: "loc_#{i}"})
      end

      # Send one more command that should be dropped
      assert :ok = Runtime.act_async(pid, :move, %{destination: :overflow_location})

      # Verify overflow event was emitted with correct data
      assert_receive %Signal{
        type: "jido.agent.queue_overflow",
        data: %{
          queue_size: ^max_size,
          max_size: ^max_size,
          dropped_command: {:act, %{command: :move, destination: :overflow_location}}
        }
      }
    end

    test "processes queued commands after resume", %{worker: pid, max_queue_size: max_size} do
      # Queue up commands - using simple move commands
      for _i <- 1..max_size do
        assert :ok = Runtime.act_async(pid, :move, %{destination: :kitchen})
      end

      # Resume worker and wait for state change
      {:ok, _} = Runtime.manage(pid, :resume)
      assert_receive %Signal{type: "jido.agent.state_changed", data: %{to: :running}}

      # Wait for either completion or failure signals
      for _ <- 1..max_size do
        receive do
          %Signal{type: "jido.agent.act_completed"} -> :ok
          %Signal{type: "jido.agent.act_failed"} -> :ok
        after
          1000 -> flunk("Command processing timeout")
        end
      end

      # Verify the state has changed in some way
      state = :sys.get_state(pid)
      refute state.agent.state.location == :home
    end

    test "handles custom max queue size", %{agent: _agent} do
      custom_size = 5
      # Create a new agent with a unique ID
      agent = SimpleAgent.new("test_agent_custom_queue")

      {:ok, pid} =
        Runtime.start_link(
          agent: agent,
          pubsub: TestPubSub,
          topic: "test.topic",
          max_queue_size: custom_size
        )

      # First resume to get to running state, then pause to force command queueing
      {:ok, _} = Runtime.manage(pid, :resume)
      {:ok, _} = Runtime.manage(pid, :pause)

      # Fill queue to custom capacity
      for i <- 1..custom_size do
        assert :ok = Runtime.act_async(pid, :move, %{destination: "loc_#{i}"})
      end

      # Verify next command is dropped
      assert :ok = Runtime.act_async(pid, :move, %{destination: :overflow_location})

      assert_receive %Signal{
        type: "jido.agent.queue_overflow",
        data: %{
          queue_size: ^custom_size,
          max_size: ^custom_size,
          dropped_command: {:act, %{command: :move, destination: :overflow_location}}
        }
      }
    end

    test "uses default max queue size when not specified", %{agent: _agent} do
      # Create a new agent with a unique ID
      agent = SimpleAgent.new("test_agent_default_queue")

      {:ok, pid} =
        Runtime.start_link(
          agent: agent,
          pubsub: TestPubSub,
          topic: "test.topic"
        )

      # First resume to get to running state to match other tests
      {:ok, _} = Runtime.manage(pid, :resume)

      state = :sys.get_state(pid)
      assert state.max_queue_size == 10_000
    end
  end
end
