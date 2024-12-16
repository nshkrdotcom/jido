defmodule JidoTest.Workflow.ChainTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Error
  alias Jido.Workflow.Chain
  alias JidoTest.TestActions.Add
  alias JidoTest.TestActions.ContextAwareMultiply
  alias JidoTest.TestActions.ErrorAction
  alias JidoTest.TestActions.Multiply
  alias JidoTest.TestActions.Square
  alias JidoTest.TestActions.Subtract
  alias JidoTest.TestActions.WriteFile

  setup_all do
    original_level = Logger.level()
    Logger.configure(level: :debug)

    on_exit(fn ->
      Logger.configure(level: original_level)
    end)

    :ok
  end

  describe "chain/3" do
    test "executes a simple chain of workflows successfully" do
      capture_log(fn ->
        result = Chain.chain([Add, Multiply], %{value: 5, amount: 2})
        assert {:ok, %{value: 14, amount: 2}} = result
      end)
    end

    test "supports new syntax with workflow options" do
      capture_log(fn ->
        result =
          Chain.chain(
            [
              Add,
              {WriteFile, [file_name: "test.txt", content: "Hello"]},
              Multiply
            ],
            %{value: 1, amount: 2}
          )

        assert {:ok, %{value: 6, written_file: "test.txt"}} = result
      end)
    end

    test "executes a chain with mixed workflow formats" do
      capture_log(fn ->
        result = Chain.chain([Add, {Multiply, [amount: 3]}, Subtract], %{value: 5})
        assert {:ok, %{value: 15, amount: 3}} = result
      end)
    end

    test "handles errors in the chain" do
      capture_log(fn ->
        result = Chain.chain([Add, ErrorAction, Multiply], %{value: 5, error_type: :runtime})
        assert {:error, %Error{type: :execution_error, message: message}} = result
        assert message =~ "Runtime error"
      end)
    end

    test "stops execution on first error" do
      capture_log(fn ->
        result = Chain.chain([Add, ErrorAction, Multiply], %{value: 5, error_type: :runtime})
        assert {:error, %Error{}} = result
        refute match?({:ok, %{value: _}}, result)
      end)
    end

    test "handles invalid workflows in the chain" do
      capture_log(fn ->
        result = Chain.chain([Add, :invalid_workflow, Multiply], %{value: 5})

        assert {:error,
                %Error{
                  type: :invalid_action,
                  message: "Failed to compile module :invalid_workflow: :nofile"
                }} =
                 result
      end)
    end

    test "executes chain asynchronously" do
      capture_log(fn ->
        task = Chain.chain([Add, Multiply], %{value: 5}, async: true)
        assert %Task{} = task
        assert {:ok, %{value: 12}} = Task.await(task)
      end)
    end

    test "passes context to workflows" do
      capture_log(fn ->
        context = %{multiplier: 3}
        result = Chain.chain([Add, ContextAwareMultiply], %{value: 5}, context: context)
        assert {:ok, %{value: 18}} = result
      end)
    end

    test "logs debug messages for each workflow" do
      log =
        capture_log(fn ->
          Chain.chain([Add, Multiply], %{value: 5}, timeout: 10)
        end)

      # assert log =~ "Executing workflow in chain"
      assert log =~ "Action Elixir.JidoTest.TestActions.Add complete"
      assert log =~ "Action Elixir.JidoTest.TestActions.Multiply complete"
    end

    test "logs warnings for failed workflows" do
      log =
        capture_log(fn ->
          Chain.chain([Add, ErrorAction], %{value: 5, error_type: :runtime, timeout: 10})
        end)

      assert log =~ "Workflow in chain failed"
      assert log =~ "Action Elixir.JidoTest.TestActions.ErrorAction error"
    end

    test "executes a complex chain of workflows" do
      capture_log(fn ->
        result =
          Chain.chain(
            [
              Add,
              {Multiply, [amount: 3]},
              Subtract,
              {Square, [amount: 2]}
            ],
            %{value: 10}
          )

        assert {:ok, %{value: 900}} = result
      end)
    end
  end
end
