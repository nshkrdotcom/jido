defmodule Jido.Agent.Server.OutputTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  require Jido.Agent.Server.Output
  require Logger

  alias Jido.Agent.Server.Output
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal

  defmodule TestDirective do
    defstruct [:type, :data]
  end

  @moduletag :capture_log

  setup do
    # Configure logger for tests
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)

    agent = %{id: "test-agent-123"}

    state = %ServerState{
      causation_id: "cause-456",
      correlation_id: "corr-123",
      child_supervisor: nil,
      max_queue_size: 10000,
      pending_signals: {[], []},
      status: :idle,
      mode: :auto,
      verbose: true,
      dispatch: {Jido.Signal.Dispatch.NoopAdapter, []},
      agent: agent
    }

    {:ok, state: state}
  end

  describe "emit_event/3" do
    test "emits event and logs when verbose", %{state: state} do
      log =
        capture_log(fn ->
          assert :ok = Output.emit_event(state, ServerSignal.cmd_success(), %{data: "test"})
        end)

      assert log =~ "[info]"
      assert log =~ "Emitting event"
    end

    test "emits event without logging when not verbose", %{state: state} do
      state = %{state | verbose: false}

      log =
        capture_log(fn ->
          assert :ok = Output.emit_event(state, ServerSignal.cmd_success(), %{data: "test"})
        end)

      refute log =~ "Emitting event"
    end

    test "handles error from build_event", %{state: state} do
      log =
        capture_log(fn ->
          assert {:error, _} =
                   Output.emit_event(state, "", %{data: "test"})
        end)

      assert log =~ "Emitting event"
    end
  end

  describe "emit_cmd/4" do
    test "emits command and logs when verbose", %{state: state} do
      log =
        capture_log(fn ->
          assert :ok = Output.emit_cmd(state, :test_cmd, %{param: "value"})
        end)

      assert log =~ "[info]"
      assert log =~ "Emitting command"
      assert log =~ "test_cmd"
    end

    test "emits command without logging when not verbose", %{state: state} do
      state = %{state | verbose: false}

      log =
        capture_log(fn ->
          assert :ok = Output.emit_cmd(state, :test_cmd, %{param: "value"})
        end)

      refute log =~ "Emitting command"
    end

    test "handles error from build_cmd", %{state: state} do
      log =
        capture_log(fn ->
          assert {:error, _} =
                   Output.emit_cmd(state, %{invalid: "instruction"}, %{param: "value"})
        end)

      assert log =~ "Emitting command"
    end
  end

  describe "emit_directive/2" do
    test "emits directive and logs when verbose", %{state: state} do
      directive = %TestDirective{type: :test_directive, data: "test"}

      log =
        capture_log(fn ->
          assert :ok = Output.emit_directive(state, directive)
        end)

      assert log =~ "[info]"
      assert log =~ "Emitting directive"
    end

    test "emits directive without logging when not verbose", %{state: state} do
      state = %{state | verbose: false}
      directive = %TestDirective{type: :test_directive, data: "test"}

      log =
        capture_log(fn ->
          assert :ok = Output.emit_directive(state, directive)
        end)

      refute log =~ "Emitting directive"
    end

    test "handles error from build_directive", %{state: state} do
      log =
        capture_log(fn ->
          assert {:error, :invalid_directive} =
                   Output.emit_directive(state, %{not_a_struct: true})
        end)

      assert log =~ "Emitting directive"
    end
  end

  describe "log_message/3" do
    test "logs message with metadata when verbose", %{state: state} do
      log =
        capture_log(fn ->
          Output.log_message(state, :info, "Test message")
        end)

      assert log =~ "[info]"
      assert log =~ "Test message"
    end

    test "does not log when not verbose", %{state: state} do
      state = %{state | verbose: false}

      log =
        capture_log(fn ->
          Output.log_message(state, :info, "Test message")
        end)

      refute log =~ "Test message"
    end

    test "logs when message level is higher than verbose level", %{state: state} do
      state = %{state | verbose: :info}

      log =
        capture_log(fn ->
          Output.log_message(state, :error, "Error message")
        end)

      assert log =~ "Error message"
    end

    test "does not log when message level is lower than verbose level", %{state: state} do
      state = %{state | verbose: :error}

      log =
        capture_log(fn ->
          Output.log_message(state, :info, "Info message")
        end)

      refute log =~ "Info message"
    end
  end

  describe "capture_result/3" do
    test "handles successful result", %{state: state} do
      log =
        capture_log(fn ->
          assert {:ok, _state} = Output.capture_result(state, {:ok, "success"})
        end)

      assert log =~ "Successfully executed"
      assert log =~ "success"
    end

    test "handles error result", %{state: state} do
      log =
        capture_log(fn ->
          assert {:error, :test_error} = Output.capture_result(state, {:error, :test_error})
        end)

      assert log =~ "Execution failed"
      assert log =~ "test_error"
    end
  end

  describe "with_logger_metadata/2" do
    test "sets and resets metadata around block", %{state: state} do
      log =
        capture_log(fn ->
          Output.with_logger_metadata state do
            Logger.info("Test with metadata")
          end

          Logger.info("Test without metadata")
        end)

      assert log =~ "[info] Test with metadata"
      assert log =~ "[info] Test without metadata"
    end
  end
end
