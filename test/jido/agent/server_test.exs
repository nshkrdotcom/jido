# defmodule JidoTest.Agent.ServerTest do
#   use ExUnit.Case, async: true
#   alias Jido.Agent.Server
#   alias Jido.Agent.Server.PubSub, as: ServerPubSub
#   alias Jido.Agent.Server.Signal, as: ServerSignal
#   alias Jido.Signal
#   alias JidoTest.TestAgents.BasicAgent

#   setup do
#     test_id = :erlang.unique_integer([:positive])
#     pubsub_name = :"TestPubSub#{test_id}"
#     registry_name = :"TestRegistry#{test_id}"
#     {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})
#     {:ok, _} = start_supervised({Registry, keys: :unique, name: registry_name})

#     agent_id = "test_agent_#{test_id}"

#     base_opts = [
#       pubsub: pubsub_name,
#       registry: registry_name,
#       max_queue_size: 100
#     ]

#     basic_opts =
#       Keyword.merge(base_opts,
#         agent: BasicAgent.new(agent_id),
#         name: :"basic_server_#{test_id}"
#       )

#     {:ok,
#      pubsub: pubsub_name,
#      registry: registry_name,
#      agent_id: agent_id,
#      base_opts: base_opts,
#      basic_opts: basic_opts}
#   end

#   describe "initialization" do
#     test "starts with correct initial state", %{basic_opts: opts} do
#       {:ok, server} = start_supervised({Server, opts})

#       assert {:ok, :idle} = Server.get_status(server)
#       assert {:ok, supervisor} = Server.get_supervisor(server)
#       assert is_pid(supervisor)
#     end

#     test "subscribes to PubSub and emits started event", %{pubsub: pubsub, agent_id: agent_id} do
#       topic = ServerPubSub.generate_topic(agent_id)
#       :ok = Phoenix.PubSub.subscribe(pubsub, topic)

#       {:ok, server} =
#         start_supervised({Server, [agent: BasicAgent.new(agent_id), pubsub: pubsub]})

#       assert {:ok, ^topic} = Server.get_topic(server)

#       started = ServerSignal.started()
#       assert_receive %Signal{type: ^started, data: %{agent_id: ^agent_id}}, 1000
#     end

#     test "validates required options", %{base_opts: opts} do
#       assert {:error, _} = Server.start_link(Keyword.merge(opts, agent: nil))
#       assert {:error, _} = Server.start_link(Keyword.delete(opts, :pubsub))
#       assert {:error, _} = Server.start_link(Keyword.delete(opts, :registry))
#     end
#   end

#   #   describe "command handling" do
#   #     test "executes commands and returns updated state", %{basic_opts: opts} do
#   #       {:ok, server} = start_supervised({Server, opts})

#   #       assert {:ok, state1} = Server.cmd(server, {JidoTest.TestActions.BasicAction, %{value: 1}})
#   #       assert state1.status == :idle

#   #       assert {:ok, state2} = Server.cmd(server, {JidoTest.TestActions.NoSchema, %{}})
#   #       assert state2.status == :idle
#   #     end

#   #     test "maintains command order", %{basic_opts: opts} do
#   #       {:ok, server} = start_supervised({Server, opts})

#   #       commands = [
#   #         {JidoTest.TestActions.BasicAction, %{value: 1}},
#   #         {JidoTest.TestActions.BasicAction, %{value: 2}},
#   #         {JidoTest.TestActions.BasicAction, %{value: 3}}
#   #       ]

#   #       results =
#   #         Enum.map(commands, fn cmd_tuple ->
#   #           Server.cmd(server, cmd_tuple)
#   #         end)

#   #       assert Enum.all?(results, &match?({:ok, _}, &1))
#   #     end

#   #     # test "enforces queue size limits", %{basic_opts: opts} do
#   #     #   opts = Keyword.put(opts, :max_queue_size, 5)
#   #     #   {:ok, server} = start_supervised({Server, opts})

#   #     #   results =
#   #     #     for _ <- 1..10 do
#   #     #       Server.cmd(server, {JidoTest.TestActions.NoSchema, %{}})
#   #     #     end

#   #     #   assert length(results) > 0
#   #     #   assert Enum.any?(results, &match?({:error, :queue_full}, &1))
#   #     # end
#   #   end

#   describe "state management" do
#     test "get_id returns agent id", %{basic_opts: opts} do
#       {:ok, server} = start_supervised({Server, opts})
#       assert {:ok, id} = Server.get_id(server)
#       assert is_binary(id)
#     end

#     test "get_state returns full state", %{basic_opts: opts} do
#       {:ok, server} = start_supervised({Server, opts})
#       assert {:ok, state} = Server.get_state(server)
#       assert state.status == :idle
#       assert state.pubsub == opts[:pubsub]
#       assert state.topic == ServerPubSub.generate_topic(state.agent.id)
#     end
#   end

#   describe "process lifecycle" do
#     test "terminates cleanly with supervisor", %{basic_opts: opts} do
#       {:ok, server} = start_supervised({Server, opts})
#       {:ok, supervisor} = Server.get_supervisor(server)

#       ref = Process.monitor(server)
#       :ok = stop_supervised(Server)

#       assert_receive {:DOWN, ^ref, :process, _, :shutdown}
#       refute Process.alive?(supervisor)
#     end

#     test "emits stopping signal on termination", %{basic_opts: opts} do
#       {:ok, server} = start_supervised({Server, opts})
#       {:ok, topic} = Server.get_topic(server)
#       :ok = Phoenix.PubSub.subscribe(opts[:pubsub], topic)

#       :ok = stop_supervised(Server)
#       refute Process.alive?(server)

#       # stopped = ServerSignal.stopped()
#       # assert_receive %Signal{type: ^stopped, data: %{reason: :shutdown}}, 1000
#     end
#   end
# end
