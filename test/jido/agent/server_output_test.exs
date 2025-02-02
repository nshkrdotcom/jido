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
      output: [
        out: {Jido.Signal.Dispatch.LoggerAdapter, []},
        log: {Jido.Signal.Dispatch.LoggerAdapter, []},
        err: {Jido.Signal.Dispatch.NoopAdapter, []}
      ],
      router: Jido.Signal.Router.new(),
      skills: [],
      status: :idle,
      pending_signals: [],
      max_queue_size: 10_000
    }

    {:ok, %{state: state, test_pid: test_pid, original_log_level: original_level}}
  end

  describe "emit_signal/3" do
    test "emits signal with default out channel", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit_signal(state, signal)
          Process.sleep(50)
        end)

      # Verify log contains all important signal information
      assert log =~ "Signal dispatched"
      assert log =~ "test.signal"
      assert log =~ "test"
      assert log =~ "Elixir.Jido.Agent.Server.OutputTest"
    end

    test "handles signal with jido_output dispatch config", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          jido_output: {Jido.Signal.Dispatch.NoopAdapter, []}
        })

      # Override the state's output config to use NoopAdapter to avoid logging
      state = %{state | output: [out: {Jido.Signal.Dispatch.NoopAdapter, []}]}

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit_signal(state, signal)

          assert_receive {:dispatch, %Signal{type: "test.signal", data: "test"}, []},
                         @receive_timeout
        end)

      assert log == ""
    end

    test "handles signal with multiple jido_output dispatch configs", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          jido_output: [
            {Jido.Signal.Dispatch.NoopAdapter, []},
            {Jido.Signal.Dispatch.NoopAdapter, [test: true]}
          ]
        })

      # Override the state's output config to use NoopAdapter to avoid logging
      state = %{state | output: [out: {Jido.Signal.Dispatch.NoopAdapter, []}]}

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit_signal(state, signal)

          assert_receive {:dispatch, %Signal{type: "test.signal", data: "test"}, []},
                         @receive_timeout

          assert_receive {:dispatch, %Signal{type: "test.signal", data: "test"}, [test: true]},
                         @receive_timeout
        end)

      assert log == ""
    end

    test "handles both jido_output and channel dispatch configs", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          jido_output: {Jido.Signal.Dispatch.NoopAdapter, [jido_output: true]}
        })

      # Override the state's output config to use NoopAdapter to avoid logging
      state = %{state | output: [out: {Jido.Signal.Dispatch.NoopAdapter, [channel: true]}]}

      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit_signal(state, signal)

          assert_receive {:dispatch, %Signal{type: "test.signal", data: "test"},
                          [jido_output: true]},
                         @receive_timeout

          assert_receive {:dispatch, %Signal{type: "test.signal", data: "test"}, [channel: true]},
                         @receive_timeout
        end)

      assert log == ""
    end

    test "includes state correlation and causation IDs when signal IDs are nil", %{state: state} do
      correlation_id = "test-correlation-123"
      causation_id = "test-causation-456"

      state = %{
        state
        | current_correlation_id: correlation_id,
          current_causation_id: causation_id
      }

      # Create a signal with explicitly nil IDs
      signal = %Signal{
        type: "test.signal",
        data: "test",
        id: UUID.uuid4(),
        source: "test",
        specversion: "1.0.2",
        jido_correlation_id: nil,
        jido_causation_id: nil
      }

      assert :ok =
               Output.emit_signal(state, signal, dispatch: {Jido.Signal.Dispatch.NoopAdapter, []})

      assert_receive {:dispatch,
                      %Signal{
                        type: "test.signal",
                        data: "test",
                        jido_correlation_id: ^correlation_id,
                        jido_causation_id: ^causation_id
                      }, []},
                     @receive_timeout
    end

    test "preserves existing signal correlation and causation IDs", %{state: state} do
      state_correlation_id = "state-correlation-123"
      state_causation_id = "state-causation-456"
      signal_correlation_id = "signal-correlation-789"
      signal_causation_id = "signal-causation-012"

      state = %{
        state
        | current_correlation_id: state_correlation_id,
          current_causation_id: state_causation_id
      }

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          jido_correlation_id: signal_correlation_id,
          jido_causation_id: signal_causation_id
        })

      assert :ok =
               Output.emit_signal(state, signal, dispatch: {Jido.Signal.Dispatch.NoopAdapter, []})

      assert_receive {:dispatch,
                      %Signal{
                        type: "test.signal",
                        data: "test",
                        jido_correlation_id: ^signal_correlation_id,
                        jido_causation_id: ^signal_causation_id
                      }, []},
                     @receive_timeout
    end

    test "allows overriding correlation and causation IDs via opts", %{state: state} do
      state_correlation_id = "state-correlation-123"
      state_causation_id = "state-causation-456"
      signal_correlation_id = "signal-correlation-789"
      signal_causation_id = "signal-causation-012"
      opts_correlation_id = "opts-correlation-345"
      opts_causation_id = "opts-causation-678"

      state = %{
        state
        | current_correlation_id: state_correlation_id,
          current_causation_id: state_causation_id
      }

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          data: "test",
          jido_correlation_id: signal_correlation_id,
          jido_causation_id: signal_causation_id
        })

      assert :ok =
               Output.emit_signal(state, signal,
                 dispatch: {Jido.Signal.Dispatch.NoopAdapter, []},
                 correlation_id: opts_correlation_id,
                 causation_id: opts_causation_id
               )

      assert_receive {:dispatch,
                      %Signal{
                        type: "test.signal",
                        data: "test",
                        jido_correlation_id: ^opts_correlation_id,
                        jido_causation_id: ^opts_causation_id
                      }, []},
                     @receive_timeout
    end

    test "emits signal with override dispatch config", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      # First capture the log to ensure it's not logged
      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit_signal(state, signal,
                     dispatch: {Jido.Signal.Dispatch.NoopAdapter, []}
                   )

          assert_receive {:dispatch, %Signal{type: "test.signal", data: "test"}, []},
                         @receive_timeout
        end)

      assert log == ""
    end

    test "handles list of dispatch configs", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "test.signal", data: "test"})

      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit_signal(state, signal,
                     dispatch: [
                       {Jido.Signal.Dispatch.LoggerAdapter, []},
                       {Jido.Signal.Dispatch.NoopAdapter, []}
                     ]
                   )

          assert_receive {:dispatch, %Signal{type: "test.signal", data: "test"}, []},
                         @receive_timeout

          Process.sleep(50)
        end)

      assert log =~ "Signal dispatched"
      assert log =~ "test.signal"
    end
  end

  describe "emit_out/3" do
    test "emits data through out channel", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit_out(state, "test data")
          Process.sleep(50)
        end)

      assert log =~ "Signal dispatched"
      assert log =~ "jido.agent.out"
      assert log =~ "test data"
    end

    test "processes data through agent callback when available", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit_out(state, {:ok, "success"},
                     dispatch: {Jido.Signal.Dispatch.NoopAdapter, []}
                   )

          assert_receive {:dispatch, %Signal{type: "jido.agent.out", data: processed_data}, []},
                         @receive_timeout

          assert match?(
                   {:error, %{result: {:ok, "success"}, signal: %SignalOutputAgent{}}},
                   processed_data
                 )
        end)

      assert log == ""
    end

    test "handles data without agent callback", %{state: state} do
      state = %{state | agent: nil}

      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit_out(state, "raw data",
                     dispatch: {Jido.Signal.Dispatch.NoopAdapter, []}
                   )

          assert_receive {:dispatch, %Signal{type: "jido.agent.out", data: "raw data"}, []},
                         @receive_timeout
        end)

      assert log == ""
    end

    test "respects custom dispatch config", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit_out(state, "test data",
                     dispatch: {Jido.Signal.Dispatch.NoopAdapter, []}
                   )

          assert_receive {:dispatch, %Signal{type: "jido.agent.out", data: _}, []},
                         @receive_timeout
        end)

      assert log == ""
    end
  end

  describe "emit_log/4" do
    setup %{state: state} do
      # Ensure clean log state for each test
      Logger.flush()
      {:ok, state: state}
    end

    test "emits log message through log channel", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          assert :ok = Output.emit_log(state, :info, "test message")
          Process.sleep(50)
        end)

      assert log =~ "Signal dispatched"
      assert log =~ "jido.agent.log.info"
      assert log =~ "test message"
    end

    test "respects custom dispatch config", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit_log(state, :info, "test message",
                     dispatch: {Jido.Signal.Dispatch.NoopAdapter, []}
                   )

          assert_receive {:dispatch, %Signal{type: "jido.agent.log.info", data: "test message"},
                          []},
                         @receive_timeout
        end)

      refute log =~ "Action"
      assert log == ""
    end

    test "supports different log levels", %{state: state} do
      levels = [:debug, :info, :warning, :error]

      Enum.each(levels, fn level ->
        # Configure logger to capture the specific level
        Logger.configure(level: level)
        Logger.flush()

        message = "#{level} message"
        type = "jido.agent.log.#{level}"

        log =
          capture_log([level: level], fn ->
            assert :ok =
                     Output.emit_log(state, level, message,
                       dispatch: {Jido.Signal.Dispatch.NoopAdapter, []}
                     )

            assert_receive {:dispatch, %Signal{type: ^type, data: ^message}, []}, @receive_timeout
          end)

        refute log =~ "Action"
        assert log == ""
      end)
    end
  end

  describe "emit_err/4" do
    test "emits error through err channel", %{state: state} do
      assert :ok = Output.emit_err(state, "test error", %{code: 123})

      assert_receive {:dispatch,
                      %Signal{
                        type: "jido.agent.error",
                        data: %{
                          message: "test error",
                          metadata: %{code: 123},
                          agent_id: "test-agent-123",
                          timestamp: %DateTime{}
                        }
                      }, []},
                     @receive_timeout
    end

    test "respects custom dispatch config", %{state: state} do
      log =
        capture_log([level: :info], fn ->
          assert :ok =
                   Output.emit_err(state, "test error", %{},
                     dispatch: {Jido.Signal.Dispatch.LoggerAdapter, []}
                   )

          Process.sleep(50)
        end)

      assert log =~ "Signal dispatched"
      assert log =~ "jido.agent.error"
      assert log =~ "test error"
    end

    test "includes default metadata when none provided", %{state: state} do
      assert :ok = Output.emit_err(state, "test error")

      assert_receive {:dispatch,
                      %Signal{
                        type: "jido.agent.error",
                        data: %{
                          message: "test error",
                          metadata: %{},
                          agent_id: "test-agent-123",
                          timestamp: %DateTime{}
                        }
                      }, []},
                     @receive_timeout
    end

    test "merges provided metadata with defaults", %{state: state} do
      metadata = %{code: 500, reason: :internal_error}
      assert :ok = Output.emit_err(state, "test error", metadata)

      assert_receive {:dispatch,
                      %Signal{
                        type: "jido.agent.error",
                        data: %{
                          message: "test error",
                          metadata: ^metadata,
                          agent_id: "test-agent-123",
                          timestamp: %DateTime{}
                        }
                      }, []},
                     @receive_timeout
    end
  end

  # describe "emit_result/4" do
  #   test "processes string success result", %{state: state} do
  #     :ok = Output.emit_result(state, nil, {:ok, "success"})
  #     assert_receive {:dispatch, %Signal{data: {:processed_string, "SUCCESS"}}, []}
  #   end

  #   test "processes map success result", %{state: state} do
  #     :ok = Output.emit_result(state, nil, {:ok, %{status: :complete, value: 42}})

  #     assert_receive {:dispatch,
  #                     %Signal{data: %{status: :complete, value: 42, processed_at: %DateTime{}}},
  #                     []}
  #   end

  #   test "processes error result", %{state: state} do
  #     :ok = Output.emit_result(state, nil, {:error, :test_error})

  #     assert_receive {:dispatch,
  #                     %Signal{
  #                       data: {:wrapped_error, %{reason: :test_error, agent_id: "test-agent-123"}}
  #                     }, []}
  #   end

  #   test "processes unhandled result type", %{state: state} do
  #     unhandled = {:unhandled_type, :test_value}
  #     :ok = Output.emit_result(state, nil, unhandled)

  #     assert_receive {:dispatch,
  #                     %Signal{
  #                       data:
  #                         {:unhandled,
  #                          %SignalOutputAgent{state: %{processed_results: [^unhandled | _]}}}
  #                     }, []}
  #   end

  #   test "handles result without agent callback", %{state: state} do
  #     state = %{state | agent: nil}
  #     :ok = Output.emit_result(state, nil, {:ok, "success"})
  #     assert_receive {:dispatch, %Signal{data: {:ok, "success"}}, []}
  #   end

  #   test "passes through dispatch opts", %{state: state} do
  #     :ok = Output.emit_result(state, nil, {:ok, "success"}, dispatch: [custom: true])
  #     assert_receive {:dispatch, %Signal{data: {:processed_string, "SUCCESS"}}, custom: true}
  #   end
  # end

  # describe "emit_log/4" do
  #   test "emits log signal with default dispatch", %{state: state} do
  #     :ok = Output.emit_log(state, :info, "test message")
  #     assert_receive {:dispatch, %Signal{type: "jido.agent.log.info", data: "test message"}, []}
  #   end

  #   test "uses logger dispatch config when available", %{state: state} do
  #     state = %{
  #       state
  #       | dispatch: [
  #           default: {Jido.Signal.Dispatch.NoopAdapter, []},
  #           logger: {Jido.Signal.Dispatch.NoopAdapter, [logger: true]}
  #         ]
  #     }

  #     :ok = Output.emit_log(state, :info, "test message")

  #     assert_receive {:dispatch, %Signal{type: "jido.agent.log.info", data: "test message"},
  #                     logger: true}
  #   end

  #   test "accepts custom dispatch opts", %{state: state} do
  #     :ok = Output.emit_log(state, :info, "test message", dispatch: [custom: true])

  #     assert_receive {:dispatch, %Signal{type: "jido.agent.log.info", data: "test message"},
  #                     custom: true}
  #   end

  #   test "creates log signal with correct type and data", %{state: state} do
  #     :ok = Output.emit_log(state, :error, "error message")
  #     assert_receive {:dispatch, %Signal{type: "jido.agent.log.error", data: "error message"}, []}
  #   end
  # end
end
