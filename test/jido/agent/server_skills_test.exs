defmodule Jido.Agent.Server.SkillsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.Agent.Server.Skills
  alias Jido.Agent.Server.State, as: ServerState
  alias JidoTest.TestSkills.MockSkill
  alias Jido.Signal.Router
  alias Jido.Instruction
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestSkills.{MockSkillWithRouter}

  # Mock skill module with router function
  defmodule MockSkillWithRouter do
    def router do
      [
        %Router.Route{
          path: "test.path",
          instruction: %Instruction{action: :test_handler},
          priority: 0
        }
      ]
    end
  end

  # Mock skill module with invalid router
  defmodule InvalidRouterSkill do
    def router do
      :not_a_list
    end
  end

  # Mock skill module
  defmodule MockSkill do
    def routes do
      [
        %Router.Route{
          path: "test.path",
          instruction: %Instruction{action: :test_handler},
          priority: 0
        }
      ]
    end

    def child_spec(_) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, []},
        type: :worker
      }
    end
  end

  describe "build/2" do
    setup do
      state = %ServerState{
        agent: BasicAgent.new("test"),
        skills: [],
        router: [],
        status: :idle,
        pending_signals: [],
        max_queue_size: 1000,
        mode: :default,
        dispatch: nil,
        child_supervisor: nil,
        current_causation_id: nil,
        current_correlation_id: nil,
        log_level: :info,
        registry: nil
      }

      {:ok, state: state}
    end

    test "successfully builds state with a single skill", %{state: state} do
      opts = [skills: [MockSkill]]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert [MockSkill] == updated_state.skills
      assert Keyword.get(updated_opts, :routes) == MockSkill.routes()
      assert [MockSkill.child_spec([])] == Keyword.get(updated_opts, :child_specs)
    end

    test "handles multiple skills", %{state: state} do
      opts = [skills: [MockSkill, MockSkill]]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert [MockSkill, MockSkill] == updated_state.skills

      expected_routes = MockSkill.routes() ++ MockSkill.routes()
      assert Keyword.get(updated_opts, :routes) == expected_routes

      expected_child_specs = [MockSkill.child_spec([]), MockSkill.child_spec([])]
      assert Keyword.get(updated_opts, :child_specs) == expected_child_specs
    end

    test "returns original state when no skills provided", %{state: state} do
      opts = []
      assert {:ok, ^state, ^opts} = Skills.build(state, opts)
    end

    test "returns original state when skills is nil", %{state: state} do
      opts = [skills: nil]
      assert {:ok, ^state, ^opts} = Skills.build(state, opts)
    end

    test "returns error for invalid skills input", %{state: state} do
      opts = [skills: :not_a_list]
      assert {:error, "Skills must be a list, got: :not_a_list"} = Skills.build(state, opts)
    end

    test "accumulates routes and child_specs correctly", %{state: state} do
      existing_routes = [
        %Router.Route{
          path: "existing.path",
          instruction: %Instruction{action: :existing},
          priority: 0
        }
      ]

      existing_child_spec = %{id: :existing, start: {Module, :start_link, []}}

      opts = [
        skills: [MockSkill],
        routes: existing_routes,
        child_specs: [existing_child_spec]
      ]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert [MockSkill] == updated_state.skills

      # Check routes are combined
      assert existing_routes ++ MockSkill.routes() == Keyword.get(updated_opts, :routes)

      # Check child_specs are combined
      assert [MockSkill.child_spec([]), existing_child_spec] ==
               Keyword.get(updated_opts, :child_specs)
    end
  end
end
