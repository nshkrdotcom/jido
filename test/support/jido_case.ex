defmodule JidoTest.Case do
  @moduledoc """
  Test case helper module providing common test functionality for Jido tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import test helpers

      import JidoTest.Case
      import JidoTest.Helpers.Assertions

      @moduletag :capture_log
    end
  end

  setup _tags do
    # Setup any test state or fixtures needed
    :ok
  end
end
