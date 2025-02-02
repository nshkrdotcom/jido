defmodule JidoTest.Agent.Server.SignalTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Signal
  alias JidoTest.TestActions.{BasicAction, NoSchema}

  # Helper function to compare instructions while ignoring IDs
  defp assert_instructions_match(actual, expected) do
    actual_without_ids = Enum.map(actual, fn inst -> Map.delete(inst, :id) end)
    expected_without_ids = Enum.map(expected, fn inst -> Map.delete(inst, :id) end)
    assert actual_without_ids == expected_without_ids
  end

  describe "signal type constants" do
    test "command signal types" do
      assert ServerSignal.cmd() == "jido.agent.cmd."
      assert ServerSignal.directive() == "jido.agent.cmd.directive."
    end

    test "agent command signal types" do
      assert ServerSignal.cmd_state() == "jido.agent.cmd.state"
      assert ServerSignal.cmd_queue_size() == "jido.agent.cmd.queue_size"
      assert ServerSignal.cmd_set() == "jido.agent.cmd.set"
      assert ServerSignal.cmd_validate() == "jido.agent.cmd.validate"
      assert ServerSignal.cmd_plan() == "jido.agent.cmd.plan"
      assert ServerSignal.cmd_run() == "jido.agent.cmd.run"
    end

    test "command result signal types" do
      assert ServerSignal.cmd_failed() == "jido.agent.event.cmd.failed"
      assert ServerSignal.cmd_success() == "jido.agent.event.cmd.success"
      assert ServerSignal.cmd_success_with_syscall() == "jido.agent.event.cmd.success.syscall"

      assert ServerSignal.cmd_success_with_pending_instructions() ==
               "jido.agent.event.cmd.success.pending"
    end

    test "process lifecycle signal types" do
      assert ServerSignal.process_started() == "jido.agent.event.process.started"
      assert ServerSignal.process_terminated() == "jido.agent.event.process.terminated"
      assert ServerSignal.process_failed() == "jido.agent.event.process.failed"
      assert ServerSignal.process_error() == "jido.agent.event.process.error"
    end

    test "queue processing signal types" do
      assert ServerSignal.queue_started() == "jido.agent.event.queue.started"
      assert ServerSignal.queue_completed() == "jido.agent.event.queue.completed"
      assert ServerSignal.queue_failed() == "jido.agent.event.queue.failed"
      assert ServerSignal.queue_full() == "jido.agent.event.queue.full"
      assert ServerSignal.queue_overflow() == "jido.agent.event.queue.overflow"
      assert ServerSignal.queue_cleared() == "jido.agent.event.queue.cleared"

      assert ServerSignal.queue_processing_started() ==
               "jido.agent.event.queue.processing.started"

      assert ServerSignal.queue_processing_completed() ==
               "jido.agent.event.queue.processing.completed"

      assert ServerSignal.queue_processing_failed() == "jido.agent.event.queue.processing.failed"
      assert ServerSignal.queue_step_started() == "jido.agent.event.queue.step.started"
      assert ServerSignal.queue_step_completed() == "jido.agent.event.queue.step.completed"
      assert ServerSignal.queue_step_ignored() == "jido.agent.event.queue.step.ignored"
      assert ServerSignal.queue_step_failed() == "jido.agent.event.queue.step.failed"
    end

    test "state transition signal types" do
      assert ServerSignal.started() == "jido.agent.event.started"
      assert ServerSignal.stopped() == "jido.agent.event.stopped"
      assert ServerSignal.transition_succeeded() == "jido.agent.event.transition.succeeded"
      assert ServerSignal.transition_failed() == "jido.agent.event.transition.failed"
    end
  end

  describe "log/1" do
    test "returns correct log signal type for each level" do
      assert ServerSignal.log(:debug) == "jido.agent.log.debug"
      assert ServerSignal.log(:info) == "jido.agent.log.info"
      assert ServerSignal.log(:warn) == "jido.agent.log.warn"
      assert ServerSignal.log(:error) == "jido.agent.log.error"
      assert ServerSignal.log(:unknown) == "jido.agent.log.info"
    end
  end

  describe "build_set/3" do
    test "creates set signal with attributes" do
      state = %{agent: %{id: "agent-123"}}
      attrs = %{key: "value"}
      {:ok, signal} = ServerSignal.build_set(state, attrs)

      assert signal.type == ServerSignal.cmd_set()
      assert signal.subject == "agent-123"
      assert signal.source == "jido://agent/agent-123"

      assert_instructions_match(signal.jido_instructions, [
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: attrs,
          action: :set,
          correlation_id: nil
        }
      ])

      assert signal.jido_opts == %{strict_validation: false}
    end

    test "accepts custom validation options" do
      state = %{agent: %{id: "agent-123"}}
      attrs = %{key: "value"}
      {:ok, signal} = ServerSignal.build_set(state, attrs, strict_validation: true)

      assert signal.jido_opts == %{strict_validation: true}
    end
  end

  describe "build_validate/2" do
    test "creates validate signal" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.build_validate(state)

      assert signal.type == ServerSignal.cmd_validate()
      assert signal.subject == "agent-123"
      assert signal.source == "jido://agent/agent-123"

      assert_instructions_match(signal.jido_instructions, [
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: %{},
          action: :validate,
          correlation_id: nil
        }
      ])

      assert signal.jido_opts == %{strict_validation: false}
    end

    test "accepts custom validation options" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.build_validate(state, strict_validation: true)

      assert signal.jido_opts == %{strict_validation: true}
    end
  end

  describe "build_plan/3" do
    test "creates plan signal with single instruction" do
      state = %{agent: %{id: "agent-123"}}
      context = %{ctx: "value"}
      {:ok, signal} = ServerSignal.build_plan(state, BasicAction, context)

      assert signal.type == ServerSignal.cmd_plan()
      assert signal.subject == "agent-123"
      assert signal.source == "jido://agent/agent-123"

      assert_instructions_match(signal.jido_instructions, [
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: %{},
          action: BasicAction,
          correlation_id: nil
        }
      ])

      assert signal.jido_opts == %{context: context}
    end

    test "creates plan signal with instruction tuple" do
      state = %{agent: %{id: "agent-123"}}
      context = %{ctx: "value"}
      instruction = {BasicAction, %{arg: "value"}}
      {:ok, signal} = ServerSignal.build_plan(state, instruction, context)

      assert_instructions_match(signal.jido_instructions, [
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: %{arg: "value"},
          action: BasicAction,
          correlation_id: nil
        }
      ])

      assert signal.jido_opts == %{context: context}
    end

    test "returns error for invalid instruction format" do
      state = %{agent: %{id: "agent-123"}}

      assert {:error, "invalid instruction format"} =
               ServerSignal.build_plan(state, "invalid", %{})
    end
  end

  describe "build_run/2" do
    test "creates run signal with default options" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.build_run(state)

      assert signal.type == ServerSignal.cmd_run()
      assert signal.subject == "agent-123"
      assert signal.source == "jido://agent/agent-123"

      assert_instructions_match(signal.jido_instructions, [
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: %{},
          action: :run,
          correlation_id: nil
        }
      ])

      assert signal.jido_opts == %{runner: nil, context: %{}}
    end

    test "accepts custom runner and context" do
      state = %{agent: %{id: "agent-123"}}
      opts = [runner: :test_runner, context: %{ctx: "value"}]
      {:ok, signal} = ServerSignal.build_run(state, opts)

      assert signal.jido_opts == %{runner: :test_runner, context: %{ctx: "value"}}
    end
  end

  describe "build_cmd/4" do
    test "creates command signal with single instruction" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.build_cmd(state, BasicAction)

      assert signal.type == ServerSignal.cmd()
      assert signal.subject == "agent-123"

      assert_instructions_match(signal.jido_instructions, [
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: %{},
          action: JidoTest.TestActions.BasicAction,
          correlation_id: nil
        }
      ])

      assert signal.jido_opts == %{apply_state: true}
    end

    test "creates command signal with instruction tuple" do
      state = %{agent: %{id: "agent-123"}}
      instruction = {BasicAction, %{arg: "value"}}
      {:ok, signal} = ServerSignal.build_cmd(state, instruction)

      assert_instructions_match(signal.jido_instructions, [
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: %{arg: "value"},
          action: JidoTest.TestActions.BasicAction,
          correlation_id: nil
        }
      ])
    end

    test "creates command signal with instruction list" do
      state = %{agent: %{id: "agent-123"}}

      instructions = [
        {BasicAction, %{arg1: "val1"}},
        {NoSchema, %{arg2: "val2"}}
      ]

      {:ok, signal} = ServerSignal.build_cmd(state, instructions)

      assert_instructions_match(signal.jido_instructions, [
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: %{arg1: "val1"},
          action: JidoTest.TestActions.BasicAction,
          correlation_id: nil
        },
        %Jido.Instruction{
          opts: [],
          context: %{},
          params: %{arg2: "val2"},
          action: JidoTest.TestActions.NoSchema,
          correlation_id: nil
        }
      ])
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
