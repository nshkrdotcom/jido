defmodule JidoTest.Case do
  @moduledoc """
  Test case helper module providing common test functionality for Jido tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import test helpers

      import JidoTest.Case

      @moduletag :capture_log
    end
  end

  setup _tags do
    # Setup any test state or fixtures needed
    :ok
  end

  @doc """
  Repeatedly evaluates a function until it returns a truthy value or times out.

  This helper is particularly useful for testing asynchronous operations where the
  expected state or result may not be immediately available. It will repeatedly
  evaluate the given function at specified intervals until either:
  - The function returns a truthy value (success)
  - The timeout period is reached (failure)

  ## Examples

      # Wait for an async message with default timeout (100ms)
      assert_eventually(fn ->
        receive do
          {:signal, {:ok, signal}} -> true
          after 0 -> false
        end
      end)

      # Wait up to 1 second with custom timeout
      assert_eventually(
        fn ->
          # Check for some condition
          Process.whereis(:my_process) != nil
        end,
        1000  # timeout in milliseconds
      )

  ## Parameters

    - fun: Function that returns the condition to check
    - timeout: Maximum time to wait in milliseconds (default: 100)
    - interval: Time between checks in milliseconds (default: 10)

  ## Raises

    - ExUnit.AssertionError - When the timeout is reached before getting a truthy result
  """
  def assert_eventually(fun, timeout \\ 100, interval \\ 10)

  def assert_eventually(_fun, timeout, _interval) when timeout <= 0 do
    raise ExUnit.AssertionError,
          "Eventually assertion failed to receive a truthy result before timeout."
  end

  def assert_eventually(fun, timeout, interval) do
    result = fun.()
    ExUnit.Assertions.assert(result)
    result
  rescue
    ExUnit.AssertionError ->
      Process.sleep(interval)
      assert_eventually(fun, timeout - interval, interval)
  end
end
