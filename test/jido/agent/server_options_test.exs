defmodule Jido.Agent.Server.OptionsTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Server.Options
  alias JidoTest.TestAgents.{MinimalAgent, BasicAgent}

  describe "validate_server_opts/1" do
    test "validates minimal valid options" do
      opts = [
        agent: MinimalAgent,
        id: "test-agent"
      ]

      assert {:ok, validated} = Options.validate_server_opts(opts)
      assert Keyword.get(validated, :agent) == MinimalAgent
      assert Keyword.get(validated, :mode) == :auto
      assert Keyword.get(validated, :log_level) == :info
      assert Keyword.get(validated, :max_queue_size) == 10_000
    end

    test "validates full options set" do
      opts = [
        agent: BasicAgent,
        id: "test-agent",
        mode: :step,
        log_level: :debug,
        max_queue_size: 100,
        registry: MyRegistry,
        output: [
          out: {:logger, []},
          err: {:logger, []},
          log: {:logger, []}
        ],
        routes: [],
        sensors: [],
        skills: [],
        child_specs: []
      ]

      assert {:ok, validated} = Options.validate_server_opts(opts)
      assert Keyword.get(validated, :agent) == BasicAgent
      assert Keyword.get(validated, :mode) == :step
      assert Keyword.get(validated, :log_level) == :debug
      assert Keyword.get(validated, :max_queue_size) == 100
      assert Keyword.get(validated, :registry) == MyRegistry
    end

    test "returns error for missing required options" do
      assert {:error, _} = Options.validate_server_opts([])
      assert {:error, _} = Options.validate_server_opts(agent: MinimalAgent)
      assert {:error, _} = Options.validate_server_opts(id: "test-agent")
    end

    test "returns error for invalid option values" do
      opts = [
        agent: MinimalAgent,
        id: "test-agent",
        mode: :invalid,
        log_level: :trace,
        max_queue_size: -1
      ]

      assert {:error, _} = Options.validate_server_opts(opts)
    end
  end

  describe "validate_agent_opts/1" do
    test "validates atom module" do
      assert {:ok, MinimalAgent} = Options.validate_agent_opts(MinimalAgent)
    end

    test "validates agent struct" do
      agent = MinimalAgent.new("test-agent")
      assert {:ok, ^agent} = Options.validate_agent_opts(agent)
    end

    test "returns error for invalid agent" do
      assert {:error, :invalid_agent} = Options.validate_agent_opts("invalid")
      assert {:error, :invalid_agent} = Options.validate_agent_opts(%{})
    end
  end

  describe "validate_output_opts/1" do
    test "validates default output configuration" do
      assert {:ok, validated} = Options.validate_output_opts([])
      assert Keyword.get(validated, :out) == {:console, []}
      assert Keyword.get(validated, :err) == {:console, []}
      assert Keyword.get(validated, :log) == {:console, []}
    end

    test "validates custom output configuration" do
      config = [
        out: {:logger, level: :info},
        err: {:logger, level: :error},
        log: {:logger, []}
      ]

      assert {:ok, validated} = Options.validate_output_opts(config)
      assert Keyword.get(validated, :out) == {:logger, level: :info}
      assert Keyword.get(validated, :err) == {:logger, level: :error}
      assert Keyword.get(validated, :log) == {:logger, []}
    end
  end

  describe "validate_route_opts/1" do
    test "validates empty routes" do
      assert {:ok, []} = Options.validate_route_opts([])
    end

    test "returns error for invalid route format" do
      assert {:error, _} = Options.validate_route_opts([{"invalid"}])
      assert {:error, _} = Options.validate_route_opts([{:not_a_string, fn -> :ok end}])
    end
  end
end
