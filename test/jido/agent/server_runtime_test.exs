defmodule JidoTest.Agent.ServerRuntimeTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Server.State, as: ServerState
  alias JidoTest.TestActions.NoSchema
  alias JidoTest.TestAgents.BasicAgent

  alias Jido.Agent.Server.Runtime, as: ServerRuntime
  alias Jido.Agent.Server.Router, as: ServerRouter
  alias Jido.{Signal, Instruction}

  @moduletag :capture_log

  describe "extract_opts_from_first_instruction/1" do
    test "extracts opts from first instruction" do
      {:ok, instruction} = Instruction.new(%{action: NoSchema, opts: [foo: "bar"]})

      assert {:ok, [foo: "bar"]} =
               ServerRuntime.extract_opts_from_first_instruction([instruction])
    end

    test "returns empty list for empty instructions" do
      assert {:ok, []} = ServerRuntime.extract_opts_from_first_instruction([])
    end

    test "returns empty list when first instruction has no opts" do
      {:ok, instruction} = Instruction.new(%{action: NoSchema, opts: nil})
      assert {:ok, []} = ServerRuntime.extract_opts_from_first_instruction([instruction])
    end
  end

  describe "ensure_state/2" do
    test "returns same state when status matches target" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :running}
      assert state == ServerRuntime.ensure_state(state, :running)
    end

    test "transitions from initializing to idle" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :initializing}
      assert %ServerState{status: :idle} = ServerRuntime.ensure_state(state, :idle)
    end

    test "transitions from idle to planning" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :idle}
      assert %ServerState{status: :planning} = ServerRuntime.ensure_state(state, :planning)
    end

    test "transitions from idle to running" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :idle}
      assert %ServerState{status: :running} = ServerRuntime.ensure_state(state, :running)
    end

    test "transitions from planning to running" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :planning}
      assert %ServerState{status: :running} = ServerRuntime.ensure_state(state, :running)
    end

    test "transitions from planning to idle" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :planning}
      assert %ServerState{status: :idle} = ServerRuntime.ensure_state(state, :idle)
    end

    test "transitions from running to paused" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :running}
      assert %ServerState{status: :paused} = ServerRuntime.ensure_state(state, :paused)
    end

    test "transitions from running to idle" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :running}
      assert %ServerState{status: :idle} = ServerRuntime.ensure_state(state, :idle)
    end

    test "transitions from paused to running" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :paused}
      assert %ServerState{status: :running} = ServerRuntime.ensure_state(state, :running)
    end

    test "transitions from paused to idle" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :paused}
      assert %ServerState{status: :idle} = ServerRuntime.ensure_state(state, :idle)
    end

    test "returns same state for invalid transition" do
      state = %ServerState{agent: BasicAgent.new("test"), status: :idle}
      assert state == ServerRuntime.ensure_state(state, :paused)
    end
  end

  describe "route_signal/2" do
    test "returns error when router is nil" do
      state = %ServerState{agent: BasicAgent.new("test"), router: nil}
      signal = Signal.new!(%{type: "test"})
      assert {:error, :no_router} = ServerRuntime.route_signal(state, signal)
    end

    test "routes signal successfully" do
      {:ok, instruction} = Instruction.new(%{action: NoSchema})
      base_state = %ServerState{agent: BasicAgent.new("test")}
      {:ok, router_state} = ServerRouter.build(base_state, routes: [{"test", instruction}])
      state = %{base_state | router: router_state.router}
      signal = Signal.new!(%{type: "test"})

      assert {:ok, [%Instruction{}]} = ServerRuntime.route_signal(state, signal)
    end

    test "returns error for invalid signal" do
      base_state = %ServerState{agent: BasicAgent.new("test")}
      {:ok, instruction} = Instruction.new(%{action: NoSchema})
      {:ok, router_state} = ServerRouter.build(base_state, routes: [{"test", instruction}])
      state = %{base_state | router: router_state.router}

      assert {:error, :invalid_signal} = ServerRuntime.route_signal(state, :invalid)
    end
  end

  describe "set_correlation_id/2" do
    test "sets correlation and causation IDs from signal" do
      state = %ServerState{agent: BasicAgent.new("test")}

      signal =
        Signal.new!(%{
          type: "test",
          jido_correlation_id: "corr-123",
          jido_causation_id: "cause-456"
        })

      assert {:ok, result} = ServerRuntime.set_correlation_id(state, signal)

      assert result.current_correlation_id == "corr-123"
      assert result.current_causation_id == "cause-456"
    end
  end

  describe "set_causation_id/2" do
    test "sets causation ID from first instruction in list" do
      state = %ServerState{agent: BasicAgent.new("test")}

      {:ok, instruction1} = Instruction.new(%{action: NoSchema, id: "instr-123"})
      {:ok, instruction2} = Instruction.new(%{action: NoSchema, id: "instr-456"})
      instructions = [instruction1, instruction2]

      assert {:ok, result} = ServerRuntime.set_causation_id(state, instructions)

      assert result.current_causation_id == "instr-123"
    end

    test "sets causation ID from single instruction" do
      state = %ServerState{agent: BasicAgent.new("test")}
      {:ok, instruction} = Instruction.new(%{action: NoSchema, id: "instr-123"})

      assert {:ok, result} = ServerRuntime.set_causation_id(state, instruction)

      assert result.current_causation_id == "instr-123"
    end

    test "sets nil causation ID when instruction has no ID" do
      state = %ServerState{agent: BasicAgent.new("test")}
      {:ok, instruction} = Instruction.new(%{action: NoSchema, id: nil})

      assert {:ok, result} = ServerRuntime.set_causation_id(state, instruction)

      assert result.current_causation_id == nil
    end
  end

  describe "clear_runtime_state/1" do
    test "clears all runtime state fields" do
      signal = Signal.new!(%{type: "test"})

      state = %ServerState{
        agent: BasicAgent.new("test"),
        current_correlation_id: "corr-123",
        current_causation_id: "cause-456",
        current_signal_type: :async,
        current_signal: signal
      }

      assert result = ServerRuntime.clear_runtime_state(state)

      assert result.current_correlation_id == nil
      assert result.current_causation_id == nil
      assert result.current_signal_type == nil
      assert result.current_signal == nil
    end
  end

  describe "process_signal/2" do
    setup do
      agent = BasicAgent.new("test")

      state = %ServerState{
        agent: agent,
        dispatch: [pid: [target: self()]]
      }

      # Build router with test routes
      {:ok, instruction} =
        Instruction.new(%{
          action: JidoTest.TestActions.BasicAction,
          params: %{value: 42}
        })

      {:ok, state} =
        ServerRouter.build(state,
          routes: [
            {"test.basic", instruction}
          ]
        )

      {:ok, state: state}
    end

    test "processes synchronous signal with reply ref", %{state: state} do
      signal = %Signal{
        type: "test.basic",
        source: "test",
        id: "test-1",
        data: %{value: 42}
      }

      from = {self(), make_ref()}

      # Store reply ref and process signal
      state = ServerState.store_reply_ref(state, signal.id, from)
      {:ok, new_state, result} = ServerRuntime.process_signal(state, signal)

      # Verify reply ref was removed
      assert ServerState.get_reply_ref(new_state, signal.id) == nil
      assert result.value == 42
    end

    test "processes asynchronous signal without reply ref", %{state: state} do
      signal = %Signal{
        type: "test.basic",
        source: "test",
        id: "test-2",
        data: %{value: 42}
      }

      {:ok, new_state, result} = ServerRuntime.process_signal(state, signal)

      # Verify state and result
      assert new_state != nil
      assert result.value == 42
    end
  end
end
