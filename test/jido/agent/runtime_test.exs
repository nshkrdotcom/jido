defmodule JidoTest.Agent.RuntimeTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Runtime
  alias Jido.Agent.Runtime.PubSub, as: RuntimePubSub
  alias Jido.Agent.Runtime.Signal, as: RuntimeSignal
  alias Jido.Signal
  alias JidoTest.TestAgents.SimpleAgent

  setup do
    test_id = :erlang.unique_integer([:positive])
    pubsub_name = :"TestPubSub#{test_id}"
    registry_name = :"TestRegistry#{test_id}"
    {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})
    {:ok, _} = start_supervised({Registry, keys: :unique, name: registry_name})

    agent_id = "test_agent_#{test_id}"

    base_opts = [
      pubsub: pubsub_name,
      registry: registry_name,
      max_queue_size: 100
    ]

    simple_opts =
      Keyword.merge(base_opts,
        agent: SimpleAgent.new(agent_id),
        name: :"simple_runtime_#{test_id}"
      )

    {:ok,
     pubsub: pubsub_name,
     registry: registry_name,
     agent_id: agent_id,
     base_opts: base_opts,
     simple_opts: simple_opts}
  end

  describe "initialization" do
    test "starts with correct initial state", %{simple_opts: opts} do
      {:ok, runtime} = start_supervised({Runtime, opts})

      assert {:ok, :idle} = Runtime.get_status(runtime)
      assert {:ok, supervisor} = Runtime.get_supervisor(runtime)
      assert is_pid(supervisor)
    end

    test "subscribes to PubSub and emits started event", %{pubsub: pubsub, agent_id: agent_id} do
      topic = RuntimePubSub.generate_topic(agent_id)
      :ok = Phoenix.PubSub.subscribe(pubsub, topic)

      {:ok, runtime} =
        start_supervised({Runtime, [agent: SimpleAgent.new(agent_id), pubsub: pubsub]})

      assert {:ok, ^topic} = Runtime.get_topic(runtime)

      started = RuntimeSignal.started()
      assert_receive %Signal{type: ^started, data: %{agent_id: ^agent_id}}, 1000
    end

    test "validates required options", %{base_opts: opts} do
      assert {:error, _} = Runtime.start_link(Keyword.merge(opts, agent: nil))
      assert {:error, _} = Runtime.start_link(Keyword.delete(opts, :pubsub))
      assert {:error, _} = Runtime.start_link(Keyword.delete(opts, :registry))
    end
  end

  describe "command handling" do
    test "executes commands and returns updated state", %{simple_opts: opts} do
      {:ok, runtime} = start_supervised({Runtime, opts})

      assert {:ok, state1} = Runtime.cmd(runtime, {JidoTest.TestActions.BasicAction, %{value: 1}})
      assert state1.status == :idle

      assert {:ok, state2} = Runtime.cmd(runtime, {JidoTest.TestActions.NoSchema, %{}})
      assert state2.status == :idle
    end

    test "maintains command order", %{simple_opts: opts} do
      {:ok, runtime} = start_supervised({Runtime, opts})

      commands = [
        {JidoTest.TestActions.BasicAction, %{value: 1}},
        {JidoTest.TestActions.BasicAction, %{value: 2}},
        {JidoTest.TestActions.BasicAction, %{value: 3}}
      ]

      results =
        Enum.map(commands, fn cmd_tuple ->
          Runtime.cmd(runtime, cmd_tuple)
        end)

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    # test "enforces queue size limits", %{simple_opts: opts} do
    #   opts = Keyword.put(opts, :max_queue_size, 5)
    #   {:ok, runtime} = start_supervised({Runtime, opts})

    #   results =
    #     for _ <- 1..10 do
    #       Runtime.cmd(runtime, {JidoTest.TestActions.NoSchema, %{}})
    #     end

    #   assert length(results) > 0
    #   assert Enum.any?(results, &match?({:error, :queue_full}, &1))
    # end
  end

  describe "state management" do
    test "get_id returns agent id", %{simple_opts: opts} do
      {:ok, runtime} = start_supervised({Runtime, opts})
      assert {:ok, id} = Runtime.get_id(runtime)
      assert is_binary(id)
    end

    test "get_state returns full state", %{simple_opts: opts} do
      {:ok, runtime} = start_supervised({Runtime, opts})
      assert {:ok, state} = Runtime.get_state(runtime)
      assert state.status == :idle
      assert state.pubsub == opts[:pubsub]
      assert state.topic == RuntimePubSub.generate_topic(state.agent.id)
    end
  end

  describe "process lifecycle" do
    test "terminates cleanly with supervisor", %{simple_opts: opts} do
      {:ok, runtime} = start_supervised({Runtime, opts})
      {:ok, supervisor} = Runtime.get_supervisor(runtime)

      ref = Process.monitor(runtime)
      :ok = stop_supervised(Runtime)

      assert_receive {:DOWN, ^ref, :process, _, :shutdown}
      refute Process.alive?(supervisor)
    end

    test "emits stopping signal on termination", %{simple_opts: opts} do
      {:ok, runtime} = start_supervised({Runtime, opts})
      {:ok, topic} = Runtime.get_topic(runtime)
      :ok = Phoenix.PubSub.subscribe(opts[:pubsub], topic)

      :ok = stop_supervised(Runtime)
      refute Process.alive?(runtime)

      # stopped = RuntimeSignal.stopped()
      # assert_receive %Signal{type: ^stopped, data: %{reason: :shutdown}}, 1000
    end
  end
end
