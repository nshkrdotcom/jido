defmodule JidoTest.ServerExecDirectiveTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.Agent.Server.Execute
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias JidoTest.TestActions
  alias JidoTest.TestAgents.BasicAgent

  @moduletag :capture_log

  describe "process_signal/2 with EnqueueDirective" do
    setup do
      {:ok, supervisor} = start_supervised(DynamicSupervisor)
      agent = BasicAgent.new("test")

      state = %ServerState{
        agent: agent,
        child_supervisor: supervisor,
        dispatch: {:pid, [target: self(), delivery_mode: :async]},
        status: :idle,
        pending_signals: :queue.new()
      }

      {:ok, state: state}
    end

    test "processes and executes single enqueue directive", %{state: state} do
      {:ok, signal} =
        ServerSignal.build_cmd(
          state,
          {TestActions.EnqueueAction,
           %{action: TestActions.NoSchema, params: %{value: 4}, opts: %{apply_state: true}}},
          %{},
          apply_state: true
        )

      {:ok, final_state} = Execute.process_signal(state, signal)
      assert final_state.agent.state.result == 6
      assert final_state.agent.result == %{result: 6}
    end

    # test "processes multiple enqueue directives", %{state: state} do
    #   directives = [
    #     %EnqueueDirective{
    #       action: TestActions.Add,
    #       params: %{value: 10, amount: 1}
    #     },
    #     %EnqueueDirective{
    #       action: TestActions.Multiply,
    #       params: %{amount: 2}
    #     },
    #     %EnqueueDirective{
    #       action: TestActions.Add,
    #       params: %{amount: 8}
    #     }
    #   ]

    #   signals = Enum.map(directives, fn directive ->
    #     %Signal{
    #       type: :directive,
    #       data: directive
    #     }
    #   end)

    #   final_state =
    #     Enum.reduce(signals, state, fn signal, acc_state ->
    #       {:ok, new_state} = Execute.process_signal(acc_state, signal)
    #       new_state
    #     end)

    #   # Verify instructions were enqueued in order
    #   {:value, first} = :queue.peek(final_state.agent.pending_instructions)
    #   assert first.action == TestActions.Add
    #   assert first.params == %{value: 10, amount: 1}

    #   instructions = :queue.to_list(final_state.agent.pending_instructions)
    #   assert length(instructions) == 3

    #   [first, second, third] = instructions
    #   assert second.action == TestActions.Multiply
    #   assert second.params == %{amount: 2}
    #   assert third.action == TestActions.Add
    #   assert third.params == %{amount: 8}
    # end
  end

  describe "handle_pending_instructions" do
    setup do
      {:ok, supervisor} = start_supervised(DynamicSupervisor)
      agent = BasicAgent.new("test")

      state = %ServerState{
        agent: agent,
        child_supervisor: supervisor,
        dispatch: {:pid, [target: self(), delivery_mode: :async]},
        status: :idle,
        pending_signals: :queue.new()
      }

      {:ok, state: state}
    end

    test "converts pending instructions to signals and clears queue", %{state: state} do
      # Add some pending instructions to agent
      instructions =
        :queue.from_list([
          %{
            action: TestActions.Add,
            params: %{value: 10, amount: 1},
            opts: %{apply_state: true}
          },
          %{
            action: TestActions.Multiply,
            params: %{amount: 2},
            opts: %{apply_state: true}
          }
        ])

      # Update agent with pending instructions and result
      agent = %{
        state.agent
        | pending_instructions: instructions,
          # Initial result state
          result: %{value: 10}
      }

      state = %{state | agent: agent}

      # Call handle_pending_instructions
      {:ok, new_state} = Execute.handle_pending_instructions(state, agent)

      # Verify pending instructions were cleared
      assert :queue.is_empty(new_state.agent.pending_instructions)

      # Verify signals were added to queue
      signals = :queue.to_list(new_state.pending_signals)
      assert length(signals) == 2

      [first, second] = signals

      assert first.type == ServerSignal.cmd()

      assert first.jido_instructions == [
               %Jido.Instruction{
                 opts: [],
                 context: %{},
                 params: %{value: 10, amount: 1},
                 action: JidoTest.TestActions.Add
               }
             ]

      assert first.jido_opts == %{apply_state: true}
      assert first.data == %{}
      assert first.source =~ "jido://agent/"

      assert second.type == ServerSignal.cmd()

      assert second.jido_instructions == [
               %Jido.Instruction{
                 opts: [],
                 context: %{},
                 params: %{amount: 2},
                 action: JidoTest.TestActions.Multiply
               }
             ]

      assert second.jido_opts == %{apply_state: true}
      assert second.data == %{}
      assert second.source =~ "jido://agent/"
    end

    test "handles empty instruction queue", %{state: state} do
      # Update agent with empty instruction queue
      agent = %{state.agent | pending_instructions: :queue.new()}
      state = %{state | agent: agent}

      {:ok, new_state} = Execute.handle_pending_instructions(state, agent)

      assert :queue.is_empty(new_state.agent.pending_instructions)
      assert :queue.is_empty(new_state.pending_signals)
    end

    @tag :skip
    test "returns error if signal creation fails", %{state: state} do
      # Add invalid instruction that will fail signal creation
      instructions =
        :queue.from_list([
          %{
            # Invalid action
            action: nil,
            params: %{},
            opts: nil
          }
        ])

      # Update agent with invalid instructions
      agent = %{state.agent | pending_instructions: instructions}
      state = %{state | agent: agent}

      assert {:error, _reason} = Execute.handle_pending_instructions(state, agent)
    end
  end
end
