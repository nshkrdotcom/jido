defmodule JidoTest.ErrorTest do
  use JidoTest.Case, async: true

  alias Jido.Error

  describe "error type functions" do
    test "create specific error types" do
      for type <- [
            :bad_request,
            :validation_error,
            :config_error,
            :execution_error,
            :action_error,
            :internal_server_error,
            :timeout
          ] do
        error = apply(Error, type, ["Test message"])
        assert %Error{} = error
        assert error.type == type
        assert error.message == "Test message"
        assert error.details == nil
        assert is_list(error.stacktrace)
      end
    end

    test "create errors with details" do
      details = %{reason: "test"}

      for type <- [
            :bad_request,
            :validation_error,
            :config_error,
            :execution_error,
            :action_error,
            :internal_server_error,
            :timeout
          ] do
        error = apply(Error, type, ["Test message", details])
        assert error.details == details
      end
    end

    test "create errors with custom stacktrace" do
      custom_stacktrace = [{__MODULE__, :some_function, 2, [file: "some_file.ex", line: 10]}]

      for type <- [
            :bad_request,
            :validation_error,
            :config_error,
            :execution_error,
            :action_error,
            :internal_server_error,
            :timeout
          ] do
        error = apply(Error, type, ["Test message", nil, custom_stacktrace])
        assert error.stacktrace == custom_stacktrace
      end
    end
  end

  describe "to_map/1" do
    test "converts error struct to map" do
      error = Error.bad_request("Test message", %{field: "test"})
      map = Error.to_map(error)

      assert map == %{
               type: :bad_request,
               message: "Test message",
               details: %{field: "test"},
               stacktrace: error.stacktrace
             }
    end

    test "converts error struct to map without nil values" do
      error = Error.bad_request("Test message")
      map = Error.to_map(error)

      assert map == %{
               type: :bad_request,
               message: "Test message",
               stacktrace: error.stacktrace
             }

      refute Map.has_key?(map, :details)
    end
  end

  describe "capture_stacktrace/0" do
    test "returns a list" do
      assert is_list(Error.capture_stacktrace())
    end

    test "captures current stacktrace" do
      stacktrace = Error.capture_stacktrace()
      assert length(stacktrace) > 0
      assert {JidoTest.ErrorTest, _, _, _} = hd(stacktrace)
    end
  end

  describe "String.Chars protocol" do
    test "converts simple error to string" do
      error = Error.validation_error("Invalid input")
      assert to_string(error) == "[validation_error] Invalid input"
    end

    test "includes details in string representation" do
      error = Error.validation_error("Invalid input", %{field: "email", value: "not-an-email"})

      assert to_string(error) ==
               "[validation_error] Invalid input (field: \"email\", value: \"not-an-email\")"
    end

    test "handles nested maps in details" do
      error =
        Error.validation_error("Invalid input", %{
          nested: %{field: "email", value: "test"},
          other: "value"
        })

      assert to_string(error) ==
               "[validation_error] Invalid input (nested: %{field: \"email\", value: \"test\"}, other: \"value\")"
    end

    test "excludes nested Jido.Error from details string" do
      original = Error.execution_error("Original error")

      error =
        Error.compensation_error(original, %{
          compensated: false,
          compensation_error: "Failed to compensate",
          original_error: original
        })

      assert to_string(error) ==
               "[compensation_error] Compensation failed for: Original error (compensated: false, compensation_error: \"Failed to compensate\")"
    end
  end

  describe "Inspect protocol" do
    test "provides detailed multi-line format" do
      error = Error.validation_error("Invalid input", %{field: "email"})
      inspected = inspect(error)

      assert inspected =~ "#Jido.Error<"
      assert inspected =~ "type: :validation_error"
      assert inspected =~ ~s(message: "Invalid input")
      assert inspected =~ ~s(details: %{field: "email"})
      assert inspected =~ "stacktrace:"
      assert inspected =~ ">"
    end

    test "handles nil details" do
      error = Error.validation_error("Invalid input")
      inspected = inspect(error)

      assert inspected =~ "#Jido.Error<"
      assert inspected =~ "type: :validation_error"
      assert inspected =~ ~s(message: "Invalid input")
      refute inspected =~ "details:"
    end

    test "formats compensation errors without recursive inspection" do
      original = Error.execution_error("Original error")

      error =
        Error.compensation_error(original, %{
          compensated: false,
          compensation_error: "Failed to compensate"
        })

      inspected = inspect(error)

      assert inspected =~ "#Jido.Error<"
      assert inspected =~ "type: :compensation_error"
      assert inspected =~ "Compensation failed for: Original error"
      assert inspected =~ ~s(details: %{)
      assert inspected =~ ~s(compensated: false)
      assert inspected =~ ~s(compensation_error: "Failed to compensate")
      # Should not contain nested inspection of original_error
      refute inspected =~ ~s(#Jido.Error<.*#Jido.Error<)
    end

    test "limits stacktrace to 5 frames" do
      error = Error.validation_error("Test")
      inspected = inspect(error)

      stacktrace_lines =
        inspected
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "("))
        |> length()

      assert stacktrace_lines <= 5
    end

    test "formats with infinite limit option" do
      error = Error.validation_error("Test")
      opts = %Inspect.Opts{limit: :infinity}

      inspected =
        Inspect.Algebra.format(Inspect.inspect(error, opts), 80)
        |> IO.iodata_to_binary()

      refute inspected =~ "stacktrace:"
    end
  end
end
