defmodule Jido.Agent.Server.Skills do
  @moduledoc """
  Dedicated module to manage skills for the Agent server.

  Handles building and configuring skills, including merging their routes into the server state.
  """
  use Private
  alias Jido.Agent.Server.State, as: ServerState

  def build(%ServerState{} = state, opts) do
    case opts[:skills] do
      nil ->
        {:ok, state, opts}

      skills when is_list(skills) ->
        skills
        |> Enum.reduce_while({:ok, state, opts}, fn skill, {:ok, acc_state, acc_opts} ->
          # Add skill module to state
          updated_state = %{acc_state | skills: [skill | acc_state.skills]}

          # Get routes and child_specs from skill
          skill_routes = skill.routes()
          skill_child_specs = skill.child_spec([])

          # Merge routes and child_specs into opts
          updated_opts =
            acc_opts
            |> Keyword.update(:routes, skill_routes, &(&1 ++ skill_routes))
            |> Keyword.update(:child_specs, [skill_child_specs], &[skill_child_specs | &1])

          {:cont, {:ok, updated_state, updated_opts}}
        end)

      invalid ->
        {:error, "Skills must be a list, got: #{inspect(invalid)}"}
    end
  end
end
