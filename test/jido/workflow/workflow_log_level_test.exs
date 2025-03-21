defmodule JidoTest.WorkflowLogLevelTest do
  use JidoTest.Case, async: false
  use Mimic

  import ExUnit.CaptureLog
  alias Jido.Workflow
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.ErrorAction

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    original_level = Logger.level()

    on_exit(fn ->
      Logger.configure(level: original_level)
    end)

    {:ok, original_level: original_level}
  end

  describe "log_level option" do
    test "respects debug log level override when global level is higher" do
      # Set global level to error
      original_level = Logger.level()
      Logger.configure(level: :error)

      # Set telemetry expectations
      expect(System, :monotonic_time, 2, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      # This should override logging level to debug
      Workflow.run(BasicAction, %{value: 5}, %{}, log_level: :debug)

      # Verify the log level was restored
      assert Logger.level() == :error

      # Restore original level
      Logger.configure(level: original_level)
    end

    test "logs only at error level when specified" do
      # Set global level to debug
      original_level = Logger.level()
      Logger.configure(level: :debug)

      # Set telemetry expectations
      expect(System, :monotonic_time, 2, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      # Run with error level logging
      log =
        capture_log(fn ->
          Workflow.run(BasicAction, %{value: 5}, %{}, log_level: :error)
        end)

      # No debug logs should appear
      refute log =~ "Action Elixir.JidoTest.TestActions.BasicAction start"
      refute log =~ "Action Elixir.JidoTest.TestActions.BasicAction complete"

      # Verify global level was restored
      assert Logger.level() == :debug

      # Error logs should appear for error actions
      expect(System, :monotonic_time, 2, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      # Explicitly set debug level for the test capture
      Logger.configure(level: :debug)

      log =
        capture_log(fn ->
          # But set error level for the workflow
          Workflow.run(ErrorAction, %{}, %{}, log_level: :error)
        end)

      # The error log should be present
      assert log =~ "ErrorAction"

      # Restore original level
      Logger.configure(level: original_level)
    end

    test "restores global log level after run" do
      original_level = Logger.level()
      Logger.configure(level: :warning)

      # Set telemetry expectations
      expect(System, :monotonic_time, 2, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      # Run with debug level
      Workflow.run(BasicAction, %{value: 5}, %{}, log_level: :debug)

      # Level should be restored
      assert Logger.level() == :warning

      # Also test with exceptions
      try do
        # Run something that will raise
        Workflow.run(
          fn _, _ -> raise "Test error" end,
          %{},
          %{},
          log_level: :debug
        )
      rescue
        _ -> :ok
      end

      # Level should still be restored even after error
      assert Logger.level() == :warning

      # Restore original level
      Logger.configure(level: original_level)
    end

    test "run_async also respects log level override" do
      # Set global level to error (high)
      original_level = Logger.level()
      Logger.configure(level: :error)

      # Set telemetry expectations
      expect(System, :monotonic_time, 2, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      # Run async with debug level
      async_ref = Workflow.run_async(BasicAction, %{value: 5}, %{}, log_level: :debug)
      Workflow.await(async_ref, 1000)

      # Verify global level was restored
      assert Logger.level() == :error

      # Restore original level
      Logger.configure(level: original_level)
    end
  end
end
