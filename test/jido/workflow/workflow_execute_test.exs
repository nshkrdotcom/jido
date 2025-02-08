defmodule JidoTest.WorkflowExecuteTest do
  use JidoTest.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Error
  alias Jido.Workflow
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.ContextAction
  alias JidoTest.TestActions.DelayAction
  alias JidoTest.TestActions.ErrorAction
  alias JidoTest.TestActions.KilledAction
  alias JidoTest.TestActions.NoParamsAction
  alias JidoTest.TestActions.NormalExitAction
  alias JidoTest.TestActions.RawResultAction
  alias JidoTest.TestActions.SlowKilledAction

  @moduletag :capture_log

  describe "execute_action/3" do
    test "successfully executes a Action" do
      assert {:ok, %{value: 5}} = Workflow.execute_action(BasicAction, %{value: 5}, %{})
    end

    test "successfully executes a Action with context" do
      assert {:ok, %{result: "5 processed with context: %{context: \"test\"}"}} =
               Workflow.execute_action(ContextAction, %{input: 5}, %{context: "test"})
    end

    test "successfully executes a Action with no params" do
      assert {:ok, %{result: "No params"}} = Workflow.execute_action(NoParamsAction, %{}, %{})
    end

    test "successfully executes a Action with raw result" do
      assert {:ok, %{value: 5}} = Workflow.execute_action(RawResultAction, %{value: 5}, %{})
    end

    test "handles Action execution error" do
      assert {:error, %Error{type: :execution_error}} =
               Workflow.execute_action(ErrorAction, %{error_type: :validation}, %{})
    end

    test "handles runtime errors" do
      assert {:error, %Error{type: :execution_error, message: message}} =
               Workflow.execute_action(ErrorAction, %{error_type: :runtime}, %{})

      assert message =~ "Runtime error"
    end

    test "handles argument errors" do
      assert {:error, %Error{type: :execution_error}} =
               Workflow.execute_action(ErrorAction, %{error_type: :argument}, %{})
    end

    test "handles unexpected errors" do
      assert {:error, %Error{type: :execution_error, message: message}} =
               Workflow.execute_action(ErrorAction, %{error_type: :custom}, %{})

      assert message =~ "Server error in JidoTest.TestActions.ErrorAction: Custom error"
    end
  end

  describe "execute_action_with_timeout/4" do
    test "successfully executes a Action with no params" do
      assert {:ok, %{result: "No params"}} =
               Workflow.execute_action_with_timeout(NoParamsAction, %{}, %{}, 0)
    end

    test "executes quick action within timeout" do
      assert {:ok, %{value: 5}} ==
               Workflow.execute_action_with_timeout(BasicAction, %{value: 5}, %{}, 1000)
    end

    test "executes without forking a Task when timeout is zero" do
      initial_process_count = length(Process.list())

      result = Workflow.execute_action_with_timeout(BasicAction, %{value: 5}, %{}, 0)

      # Verify the result is correct
      assert {:ok, %{value: 5}} = result

      # Give any potential tasks time to start (though there shouldn't be any)
      Process.sleep(50)

      # Verify no new processes were created
      final_process_count = length(Process.list())
      assert_in_delta initial_process_count, final_process_count, 1
    end

    test "times out for slow action" do
      assert {:error, %Error{type: :timeout}} =
               Workflow.execute_action_with_timeout(DelayAction, %{delay: 1000}, %{}, 100)
    end

    test "handles very short timeout" do
      result = Workflow.execute_action_with_timeout(DelayAction, %{delay: 100}, %{}, 1)
      assert {:error, %Error{type: :timeout}} = result
    end

    test "handles action errors" do
      assert {:error, %Error{type: :execution_error}} =
               Workflow.execute_action_with_timeout(
                 ErrorAction,
                 %{error_type: :runtime},
                 %{},
                 1000
               )
    end

    test "handles unexpected errors during execution" do
      assert {:error, %Error{type: :execution_error, message: message}} =
               Workflow.execute_action_with_timeout(ErrorAction, %{type: :unexpected}, %{}, 1000)

      assert message =~ "Workflow failed"
    end

    test "handles errors thrown during execution" do
      assert {:error, %Error{type: :execution_error, message: message}} =
               Workflow.execute_action_with_timeout(ErrorAction, %{type: :throw}, %{}, 1000)

      assert message =~ "Caught throw: \"Action threw an error\""
    end

    test "handles :DOWN message after killing the process" do
      test_pid = self()

      spawn(fn ->
        result = Workflow.execute_action_with_timeout(SlowKilledAction, %{}, %{}, 50)
        send(test_pid, {:result, result})
      end)

      assert_receive {:result, {:error, %Error{type: :timeout}}}, 1000
    end

    test "uses default timeout when not specified" do
      assert {:ok, %{result: "Async workflow completed"}} ==
               Workflow.execute_action_with_timeout(DelayAction, %{delay: 80}, %{}, 0)
    end

    test "executes without timeout when timeout is zero" do
      assert {:ok, %{result: "Async workflow completed"}} ==
               Workflow.execute_action_with_timeout(DelayAction, %{delay: 80}, %{}, 0)
    end

    test "uses default timeout for invalid timeout value" do
      capture_log(fn ->
        assert {:ok, %{value: 5}} ==
                 Workflow.execute_action_with_timeout(BasicAction, %{value: 5}, %{}, -1)
      end)
    end

    test "handles normal exit" do
      result = Workflow.execute_action_with_timeout(NormalExitAction, %{}, %{}, 1000)
      assert {:error, %Error{type: :execution_error, message: "Task exited: :normal"}} = result
    end

    test "handles killed tasks" do
      result = Workflow.execute_action_with_timeout(KilledAction, %{}, %{}, 1000)
      assert {:error, %Error{type: :execution_error, message: "Task was killed"}} = result
    end

    test "handles concurrent action execution" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Workflow.execute_action_with_timeout(BasicAction, %{value: i}, %{}, 1000)
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, %{value: v}} -> is_integer(v) end)
    end
  end
end
