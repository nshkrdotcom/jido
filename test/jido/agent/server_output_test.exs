defmodule Jido.Agent.Server.OutputTest do
  use JidoTest.Case, async: true
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
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test", id: "test-id-123"})

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
          id: "test-id-456",
          jido_dispatch: {:pid, [target: self(), delivery_mode: :async]}
        })

      capture_log([level: :info], fn ->
        assert :ok = Output.emit(signal)

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-456"}},
                       @receive_timeout
      end)
    end

    test "handles signal with multiple jido_dispatch dispatch configs" do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          id: "test-id-789",
          jido_dispatch: [
            {:pid, [target: self(), delivery_mode: :async]},
            {:pid, [target: self(), delivery_mode: :async, test: true]}
          ]
        })

      capture_log([level: :info], fn ->
        assert :ok = Output.emit(signal)

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-789"}},
                       @receive_timeout

        assert_receive {:signal, %Signal{type: "test.signal", data: "test", id: "test-id-789"}},
                       @receive_timeout
      end)
    end

    test "handles signal with dispatch config in opts" do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test", id: "test-id-101112"})

      capture_log([level: :info], fn ->
        assert :ok =
                 Output.emit(signal,
                   dispatch: {:pid, [target: self(), delivery_mode: :async]}
                 )

        assert_receive {:signal,
                        %Signal{type: "test.signal", data: "test", id: "test-id-101112"}},
                       @receive_timeout
      end)
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
