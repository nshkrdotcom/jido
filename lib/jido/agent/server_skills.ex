defmodule Jido.Agent.Server.Skills do
  @moduledoc """
  Dedicated module to manage skills for the Agent server.

  Handles building and configuring skills, including merging their routes into the server state.
  """
  use Private
  use ExDbug, enabled: true
  alias Jido.Agent.Server.State, as: ServerState

  def build(%ServerState{} = state, opts) do
    dbug("Building skills", state: state, opts: opts)

    case opts[:skills] do
      nil ->
        dbug("No skills configured")
        {:ok, state, opts}

      skills when is_list(skills) ->
        dbug("Processing skills list", skills: skills)

        skills
        |> Enum.reduce_while({:ok, state, opts}, fn skill, {:ok, acc_state, acc_opts} ->
          dbug("Processing skill", skill: skill)

          # Add skill module to state
          updated_state = %{acc_state | skills: [skill | acc_state.skills]}
          dbug("Added skill to state", updated_state: updated_state)

          # Get routes and child_specs from skill
          skill_routes = skill.routes()
          skill_child_specs = skill.child_spec([])

          dbug("Got skill routes and child specs",
            skill_routes: skill_routes,
            skill_child_specs: skill_child_specs
          )

          # Merge routes and child_specs into opts
          updated_opts =
            acc_opts
            |> Keyword.update(:routes, skill_routes, &(&1 ++ skill_routes))
            |> Keyword.update(:child_specs, [skill_child_specs], &[skill_child_specs | &1])

          dbug("Updated options with skill config", updated_opts: updated_opts)
          {:cont, {:ok, updated_state, updated_opts}}
        end)

      invalid ->
        dbug("Invalid skills configuration", invalid: invalid)
        {:error, "Skills must be a list, got: #{inspect(invalid)}"}
    end
  end
end
