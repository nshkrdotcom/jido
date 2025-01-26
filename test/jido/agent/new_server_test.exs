defmodule JidoTest.Agent.NewServerTest do
  use ExUnit.Case, async: true
  # alias Jido.Agent.Server
  # alias Jido.Agent.Server.PubSub, as: ServerPubSub
  # alias Jido.Agent.Server.Signal, as: ServerSignal
  # alias Jido.Signal
  # alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestAgents.MinimalAgent
  @moduletag :capture_log

  # setup do
  #   test_id = :erlang.unique_integer([:positive])
  #   pubsub_name = :"TestPubSub#{test_id}"
  #   registry_name = :"TestRegistry#{test_id}"
  #   {:ok, _} = start_supervised({Phoenix.PubSub, name: pubsub_name})
  #   {:ok, _} = start_supervised({Registry, keys: :unique, name: registry_name})

  #   agent_id = "test_agent_#{test_id}"

  #   base_opts = [
  #     pubsub: pubsub_name,
  #     registry: registry_name,
  #     max_queue_size: 100
  #   ]

  #   basic_opts =
  #     Keyword.merge(base_opts,
  #       agent: BasicAgent.new(agent_id),
  #       name: :"basic_server_#{test_id}"
  #     )

  #   {:ok,
  #    pubsub: pubsub_name,
  #    registry: registry_name,
  #    agent_id: agent_id,
  #    base_opts: base_opts,
  #    basic_opts: basic_opts}
  # end

  describe "initialization" do
    # test "starts with correct initial state", %{basic_opts: opts} do
    #   {:ok, server} = start_supervised({Server, opts})

    #   assert {:ok, :idle} = Server.get_status(server)
    #   assert {:ok, supervisor} = Server.get_supervisor(server)
    #   assert is_pid(supervisor)
    # end

    # test "starts a minimal agent" do
    #   {:ok, pid} = MinimalAgent.start_link()
    #   assert is_pid(pid)
    # end
  end
end
