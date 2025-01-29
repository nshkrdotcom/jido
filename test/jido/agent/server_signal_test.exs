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

      assert signal.jido_instructions == [
               %Jido.Instruction{
                 opts: [],
                 context: %{},
                 params: %{},
                 action: JidoTest.TestActions.BasicAction
               }
             ]

      assert signal.jido_opts == %{apply_state: true}
    end

    test "creates command signal with instruction tuple" do
      state = %{agent: %{id: "agent-123"}}
      instruction = {BasicAction, %{arg: "value"}}
      {:ok, signal} = ServerSignal.build_cmd(state, instruction)

      assert signal.jido_instructions == [
               %Jido.Instruction{
                 opts: [],
                 context: %{},
                 params: %{arg: "value"},
                 action: JidoTest.TestActions.BasicAction
               }
             ]
    end

    test "creates command signal with instruction list" do
      state = %{agent: %{id: "agent-123"}}

      instructions = [
        {BasicAction, %{arg1: "val1"}},
        {NoSchema, %{arg2: "val2"}}
      ]

      {:ok, signal} = ServerSignal.build_cmd(state, instructions)

      assert signal.jido_instructions == [
               %Jido.Instruction{
                 opts: [],
                 context: %{},
                 params: %{arg1: "val1"},
                 action: JidoTest.TestActions.BasicAction
               },
               %Jido.Instruction{
                 opts: [],
                 context: %{},
                 params: %{arg2: "val2"},
                 action: JidoTest.TestActions.NoSchema
               }
             ]
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

      directive = %Jido.Agent.Directive.Enqueue{
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
end
