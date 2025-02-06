defmodule Jido.Agent.Server.OutputTest do
  use ExUnit.Case, async: true
  require Logger
  import ExUnit.CaptureLog

  alias Jido.Agent.Server.Output
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  alias JidoTest.TestAgents.SignalOutputAgent

  @receive_timeout 500

  setup do
    # Save original log level and set to :info for test isolation
    original_level = Logger.level()
    :ok = Logger.configure(level: :info)

    # Register test process for assertions
    test_pid = self()
    Process.put(:test_pid, test_pid)

    on_exit(fn ->
      Process.delete(:test_pid)
      # Restore original log level
      Logger.configure(level: original_level)
    end)

    agent = SignalOutputAgent.new("test-agent-123")

    state = %ServerState{
      agent: agent,
      dispatch: [
        {:logger, []},
        {:pid, [target: self(), delivery_mode: :async]}
      ],
      router: Jido.Signal.Router.new(),
      skills: [],
      status: :idle,
      pending_signals: [],
      max_queue_size: 10_000
    }

    {:ok, %{state: state, test_pid: test_pid, original_log_level: original_level}}
  end

  describe "emit/2" do
    test "emits signal with default channel" do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit(signal)
          Process.sleep(50)
        end)

      # Verify log contains all important signal information
      assert log =~ "Signal dispatched"
      assert log =~ "test.signal"
      assert log =~ "test"
      assert log =~ "Elixir.Jido.Agent.Server.OutputTest"
    end

    test "handles signal with jido_dispatch dispatch config" do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          jido_dispatch: {:pid, [target: self(), delivery_mode: :async]}
        })

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit(signal)

          assert_receive {:signal, %Signal{type: "test.signal", data: "test"}},
                         @receive_timeout
        end)

      assert log == ""
    end

    test "handles signal with multiple jido_dispatch dispatch configs" do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          jido_dispatch: [
            {:pid, [target: self(), delivery_mode: :async]},
            {:pid, [target: self(), delivery_mode: :async, test: true]}
          ]
        })

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit(signal)

          assert_receive {:signal, %Signal{type: "test.signal", data: "test"}},
                         @receive_timeout

          assert_receive {:signal, %Signal{type: "test.signal", data: "test"}},
                         @receive_timeout
        end)

      assert log == ""
    end

    test "handles signal with dispatch config in opts" do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit(signal,
                     dispatch: {:pid, [target: self(), delivery_mode: :async]}
                   )

          assert_receive {:signal, %Signal{type: "test.signal", data: "test"}},
                         @receive_timeout
        end)

      assert log == ""
    end

    test "handles signal with correlation and causation IDs in opts" do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      correlation_id = "test-correlation-123"
      causation_id = "test-causation-456"

      assert :ok =
               Output.emit(signal,
                 correlation_id: correlation_id,
                 causation_id: causation_id,
                 dispatch: {:pid, [target: self(), delivery_mode: :async]}
               )

      assert_receive {:signal,
                      %Signal{
                        type: "test.signal",
                        data: "test",
                        jido_correlation_id: ^correlation_id,
                        jido_causation_id: ^causation_id
                      }},
                     @receive_timeout
    end

    test "preserves existing signal correlation and causation IDs" do
      signal_correlation_id = "signal-correlation-789"
      signal_causation_id = "signal-causation-012"

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          jido_correlation_id: signal_correlation_id,
          jido_causation_id: signal_causation_id
        })

      assert :ok =
               Output.emit(signal,
                 dispatch: {:pid, [target: self(), delivery_mode: :async]}
               )

      assert_receive {:signal,
                      %Signal{
                        type: "test.signal",
                        data: "test",
                        jido_correlation_id: ^signal_correlation_id,
                        jido_causation_id: ^signal_causation_id
                      }},
                     @receive_timeout
    end

    test "handles list of dispatch configs" do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit(signal,
                     dispatch: [
                       {Jido.Signal.Dispatch.LoggerAdapter, []},
                       {:pid, [target: self(), delivery_mode: :async]}
                     ]
                   )

          assert_receive {:signal, %Signal{type: "test.signal", data: "test"}},
                         @receive_timeout

          Process.sleep(50)
        end)

      assert log =~ "Signal dispatched"
      assert log =~ "test.signal"
    end
  end
end
