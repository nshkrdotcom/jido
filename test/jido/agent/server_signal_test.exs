defmodule JidoTest.Agent.Server.SignalTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Signal
  alias JidoTest.TestActions.{BasicAction, NoSchema}

  describe "syscall_signal/3" do
    test "creates syscall signal with state" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.build_event(state, ServerSignal.process_started())

      assert signal.type == ServerSignal.process_started()
      assert signal.source == "jido://agent/agent-123"
      assert signal.subject == "agent-123"
      assert signal.data == %{}
    end
  end

  describe "event_signal/3" do
    test "creates event signal with state" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.build_event(state, ServerSignal.started())

      assert signal.type == ServerSignal.started()
      assert signal.source == "jido://agent/agent-123"
      assert signal.subject == "agent-123"
      assert signal.data == %{}
    end

    test "creates event signal with payload" do
      state = %{agent: %{id: "agent-123"}}
      payload = %{key: "value"}
      {:ok, signal} = ServerSignal.build_event(state, ServerSignal.started(), payload)

      assert signal.data == payload
    end
  end

  describe "build_cmd/4" do
    test "creates command signal with single instruction" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.build_cmd(state, BasicAction)

      assert signal.type == ServerSignal.cmd()
      assert signal.subject == "agent-123"
      assert signal.jido_instructions == [{BasicAction, %{}}]
      assert signal.jido_opts == %{apply_state: true}
    end

    test "creates command signal with instruction tuple" do
      state = %{agent: %{id: "agent-123"}}
      instruction = {BasicAction, %{arg: "value"}}
      {:ok, signal} = ServerSignal.build_cmd(state, instruction)

      assert signal.jido_instructions == [{BasicAction, %{arg: "value"}}]
    end

    test "creates command signal with instruction list" do
      state = %{agent: %{id: "agent-123"}}

      instructions = [
        {BasicAction, %{arg1: "val1"}},
        {NoSchema, %{arg2: "val2"}}
      ]

      {:ok, signal} = ServerSignal.build_cmd(state, instructions)

      assert signal.jido_instructions == instructions
    end

    test "accepts custom params and opts" do
      state = %{agent: %{id: "agent-123"}}
      params = %{custom: "value"}
      opts = [apply_state: false]
      {:ok, signal} = ServerSignal.build_cmd(state, BasicAction, params, opts)

      assert signal.data == %{}
      assert signal.jido_opts == %{apply_state: false}
    end

    test "returns error for invalid instruction format" do
      state = %{agent: %{id: "agent-123"}}
      assert {:error, "invalid instruction format"} = ServerSignal.build_cmd(state, "invalid")
    end

    test "returns error for invalid instruction tuple format" do
      state = %{agent: %{id: "agent-123"}}

      assert {:error, "invalid instruction format"} =
               ServerSignal.build_cmd(state, {BasicAction, "invalid"})
    end

    test "returns error for invalid instruction list format" do
      state = %{agent: %{id: "agent-123"}}
      invalid_instructions = [{BasicAction, "invalid"}, {NoSchema, 123}]

      assert {:error, "invalid instruction format"} =
               ServerSignal.build_cmd(state, invalid_instructions)
    end
  end

  describe "directive_signal" do
    test "creates directive signal with valid directive" do
      state = %{agent: %{id: "agent-123"}}

      directive = %Jido.Agent.Directive.EnqueueDirective{
        action: BasicAction,
        params: %{value: 1},
        context: %{}
      }

      {:ok, signal} = ServerSignal.build_directive(state, directive)

      assert signal.type == ServerSignal.directive()
      assert signal.subject == "agent-123"
      assert signal.data == %{directive: directive}
    end

    test "returns error for invalid directive" do
      state = %{agent: %{id: "agent-123"}}
      invalid_directive = %{not: "a directive"}

      assert {:error, :invalid_directive} = ServerSignal.build_directive(state, invalid_directive)
    end
  end

  describe "emit_cmd" do
    test "emits command signal" do
      state = %{
        agent: %{id: "agent-123"},
        dispatch: {:pid, [target: self(), delivery_mode: :async]}
      }

      assert :ok = ServerSignal.emit_cmd(state, BasicAction)
      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.cmd()
      assert signal.jido_instructions == [{BasicAction, %{}}]
    end

    test "returns error for invalid instruction" do
      state = %{
        agent: %{id: "agent-123"},
        dispatch: {:pid, [target: self(), delivery_mode: :async]}
      }

      assert {:error, "invalid instruction format"} = ServerSignal.emit_cmd(state, "invalid")
    end
  end

  describe "emit_directive" do
    test "emits directive signal" do
      state = %{
        agent: %{id: "agent-123"},
        dispatch: {:pid, [target: self(), delivery_mode: :async]}
      }

      directive = %Jido.Agent.Directive.EnqueueDirective{
        action: BasicAction,
        params: %{value: 1},
        context: %{}
      }

      assert :ok = ServerSignal.emit_directive(state, directive)
      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.directive()
      assert signal.data == %{directive: directive}
    end

    test "returns error for invalid directive" do
      state = %{
        agent: %{id: "agent-123"},
        dispatch: {:pid, [target: self(), delivery_mode: :async]}
      }

      assert {:error, :invalid_directive} =
               ServerSignal.emit_directive(state, %{not: "a directive"})
    end
  end

  describe "emit_event" do
    test "emits event signal" do
      state = %{
        agent: %{id: "agent-123"},
        dispatch: {:pid, [target: self(), delivery_mode: :async]}
      }

      assert :ok = ServerSignal.emit_event(state, ServerSignal.started(), %{key: "value"})
      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.started()
      assert signal.data == %{key: "value"}
    end
  end

  describe "extract_instructions/1" do
    test "extracts instructions and options from valid signal" do
      signal = %Signal{
        id: "123",
        type: "jido.agent.cmd",
        source: "jido",
        subject: "agent-123",
        jido_instructions: [{BasicAction, %{param: "value"}}],
        jido_opts: %{apply_state: true},
        data: %{arg: "value"}
      }

      assert {:ok, {instructions, data, opts}} = ServerSignal.extract_instructions(signal)
      assert instructions == [{BasicAction, %{param: "value"}}]
      assert data == %{arg: "value"}
      assert opts == [apply_state: true]
    end

    test "returns error for invalid signal format" do
      invalid_signal = %Signal{
        id: "123",
        type: "jido.agent.cmd",
        source: "jido",
        subject: "agent-123",
        jido_instructions: nil,
        jido_opts: nil
      }

      assert {:error, :invalid_signal_format} = ServerSignal.extract_instructions(invalid_signal)
    end
  end

  describe "signal type predicates" do
    setup do
      {:ok, base_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "jido.agent.test",
          subject: "test-agent"
        })

      %{base_signal: base_signal}
    end

    test "is_cmd_signal?" do
      {:ok, agent_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "jido.agent.cmd.test",
          subject: "test-agent"
        })

      {:ok, other_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "other",
          subject: "test-agent"
        })

      assert ServerSignal.is_cmd_signal?(agent_signal)
      refute ServerSignal.is_cmd_signal?(other_signal)
    end

    test "is_event_signal?" do
      {:ok, event_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "jido.agent.event.test",
          subject: "test-agent"
        })

      {:ok, other_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "other",
          subject: "test-agent"
        })

      assert ServerSignal.is_event_signal?(event_signal)
      refute ServerSignal.is_event_signal?(other_signal)
    end

    test "is_directive_signal?" do
      {:ok, directive_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "jido.agent.cmd.directive.test",
          subject: "test-agent"
        })

      {:ok, other_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "other",
          subject: "test-agent"
        })

      assert ServerSignal.is_directive_signal?(directive_signal)
      refute ServerSignal.is_directive_signal?(other_signal)
    end
  end

  describe "dispatch" do
    test "dispatches signal with state dispatch config" do
      state = %{
        agent: %{id: "agent-123"},
        dispatch: {:pid, [target: self(), delivery_mode: :async]}
      }

      {:ok, signal} = ServerSignal.build_event(state, ServerSignal.started())

      assert :ok = ServerSignal.dispatch(state, signal)
      assert_receive {:signal, ^signal}
    end

    test "dispatches signal with explicit dispatch config" do
      {:ok, signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "test",
          subject: "test-agent"
        })

      config = {:pid, [target: self(), delivery_mode: :async]}
      assert :ok = ServerSignal.dispatch(signal, config)
      assert_receive {:signal, ^signal}
    end

    test "dispatches signal synchronously" do
      me = self()

      # Start a process that will respond to sync messages
      pid =
        spawn(fn ->
          receive do
            {:"$gen_call", from, {:signal, signal}} ->
              GenServer.reply(from, :ok)
              send(me, {:received, signal})
          end
        end)

      {:ok, signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "test",
          subject: "test-agent"
        })

      config = {:pid, [target: pid, delivery_mode: :sync]}
      assert :ok = ServerSignal.dispatch(signal, config)
      assert_receive {:received, ^signal}
    end

    test "returns error when target process is not alive" do
      pid = spawn(fn -> :ok end)
      # Ensure process is dead
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      {:ok, signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "test",
          subject: "test-agent"
        })

      config = {:pid, [target: pid, delivery_mode: :async]}
      assert {:error, :process_not_alive} = ServerSignal.dispatch(signal, config)
    end
  end
end
