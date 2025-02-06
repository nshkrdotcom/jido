defmodule JidoTest.Agent.Server.SignalTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Error

  setup do
    state = %ServerState{
      agent: %{
        id: "test-agent-123"
      }
    }

    {:ok, state: state}
  end

  describe "type/1" do
    test "returns correct command signal types" do
      assert ServerSignal.type({:cmd, :set}) == ["jido", "agent", "cmd", "set"]
      assert ServerSignal.type({:cmd, :validate}) == ["jido", "agent", "cmd", "validate"]
      assert ServerSignal.type({:cmd, :plan}) == ["jido", "agent", "cmd", "plan"]
      assert ServerSignal.type({:cmd, :run}) == ["jido", "agent", "cmd", "run"]
      assert ServerSignal.type({:cmd, :cmd}) == ["jido", "agent", "cmd", "cmd"]
    end

    test "returns correct event signal types" do
      assert ServerSignal.type({:event, :started}) == ["jido", "agent", "event", "started"]
      assert ServerSignal.type({:event, :stopped}) == ["jido", "agent", "event", "stopped"]

      assert ServerSignal.type({:event, :transition_succeeded}) == [
               "jido",
               "agent",
               "event",
               "transition",
               "succeeded"
             ]

      assert ServerSignal.type({:event, :transition_failed}) == [
               "jido",
               "agent",
               "event",
               "transition",
               "failed"
             ]

      assert ServerSignal.type({:event, :queue_overflow}) == [
               "jido",
               "agent",
               "event",
               "queue",
               "overflow"
             ]

      assert ServerSignal.type({:event, :queue_cleared}) == [
               "jido",
               "agent",
               "event",
               "queue",
               "cleared"
             ]
    end

    test "returns correct process event signal types" do
      assert ServerSignal.type({:event, :process_started}) == [
               "jido",
               "agent",
               "event",
               "process",
               "started"
             ]

      assert ServerSignal.type({:event, :process_restarted}) == [
               "jido",
               "agent",
               "event",
               "process",
               "restarted"
             ]

      assert ServerSignal.type({:event, :process_terminated}) == [
               "jido",
               "agent",
               "event",
               "process",
               "terminated"
             ]

      assert ServerSignal.type({:event, :process_failed}) == [
               "jido",
               "agent",
               "event",
               "process",
               "failed"
             ]
    end

    test "returns correct error signal types" do
      assert ServerSignal.type({:err, :execution_error}) == [
               "jido",
               "agent",
               "err",
               "execution",
               "error"
             ]
    end

    test "returns correct output signal types" do
      assert ServerSignal.type({:out, :instruction_result}) == [
               "jido",
               "agent",
               "out",
               "instruction",
               "result"
             ]

      assert ServerSignal.type({:out, :signal_result}) == [
               "jido",
               "agent",
               "out",
               "signal",
               "result"
             ]
    end

    test "returns nil for unknown signal type" do
      assert ServerSignal.type({:unknown, :type}) == nil
    end
  end

  describe "cmd_signal/4" do
    test "builds set command signal", %{state: state} do
      params = %{key: "value"}
      opts = %{strict: true}
      signal = ServerSignal.cmd_signal(:set, state, params, opts)

      assert signal.type == "jido.agent.cmd.set"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.data == params
      assert signal.jido_opts == opts
    end

    test "builds validate command signal", %{state: state} do
      params = %{key: "value"}
      opts = %{strict: true}
      signal = ServerSignal.cmd_signal(:validate, state, params, opts)

      assert signal.type == "jido.agent.cmd.validate"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.data == params
      assert signal.jido_opts == opts
    end

    test "builds plan command signal", %{state: state} do
      params = %{action: "test"}
      context = %{ctx: "value"}
      signal = ServerSignal.cmd_signal(:plan, state, params, context)

      assert signal.type == "jido.agent.cmd.plan"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.data == params
      assert signal.jido_opts == context
    end

    test "builds run command signal", %{state: state} do
      opts = %{runner: :test}
      signal = ServerSignal.cmd_signal(:run, state, opts, %{})

      assert signal.type == "jido.agent.cmd.run"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.jido_opts == opts
    end

    test "builds cmd command signal", %{state: state} do
      instructions = {[:test_instruction], %{param: "value"}}
      opts = %{apply: true}
      signal = ServerSignal.cmd_signal(:cmd, state, instructions, opts)

      assert signal.type == "jido.agent.cmd.cmd"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.data == %{param: "value"}
      assert signal.jido_opts == opts
    end

    test "returns nil for unknown command type", %{state: state} do
      assert ServerSignal.cmd_signal(:unknown, state, %{}, %{}) == nil
    end
  end

  describe "event_signal/3" do
    test "builds started event signal", %{state: state} do
      params = %{status: "ok"}
      signal = ServerSignal.event_signal(:started, state, params)

      assert signal.type == "jido.agent.event.started"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.data == params
    end

    test "builds process event signals", %{state: state} do
      params = %{pid: "123"}

      signal = ServerSignal.event_signal(:process_started, state, params)
      assert signal.type == "jido.agent.event.process.started"

      signal = ServerSignal.event_signal(:process_terminated, state, params)
      assert signal.type == "jido.agent.event.process.terminated"

      signal = ServerSignal.event_signal(:process_failed, state, params)
      assert signal.type == "jido.agent.event.process.failed"

      signal = ServerSignal.event_signal(:process_restarted, state, params)
      assert signal.type == "jido.agent.event.process.restarted"
    end

    test "returns nil for unknown event type", %{state: state} do
      assert ServerSignal.event_signal(:unknown, state, %{}) == nil
    end
  end

  describe "err_signal/4" do
    test "builds execution error signal", %{state: state} do
      error = %Error{type: :execution_error, message: "test error"}
      signal = ServerSignal.err_signal(:execution_error, state, error, %{})

      assert signal.type == "jido.agent.err.execution.error"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.data == error
    end

    test "returns nil for unknown error type", %{state: state} do
      error = %Error{type: :unknown, message: "test error"}
      assert ServerSignal.err_signal(:unknown, state, error, %{}) == nil
    end
  end

  describe "out_signal/4" do
    test "builds instruction result output signal", %{state: state} do
      result = %{output: "test result"}
      signal = ServerSignal.out_signal(:instruction_result, state, result, %{})

      assert signal.type == "jido.agent.out.instruction.result"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.data == result
    end

    test "builds signal result output signal", %{state: state} do
      result = %{output: "test result"}
      signal = ServerSignal.out_signal(:signal_result, state, result, %{})

      assert signal.type == "jido.agent.out.signal.result"
      assert signal.source == "jido://agent/test-agent-123"
      assert signal.data == result
    end

    test "returns nil for unknown output type", %{state: state} do
      assert ServerSignal.out_signal(:unknown, state, %{}, %{}) == nil
    end
  end
end
