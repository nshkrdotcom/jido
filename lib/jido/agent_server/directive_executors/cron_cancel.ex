defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.CronCancel do
  @moduledoc false

  require Logger

  def exec(%{job_id: logical_id}, _input_signal, state) do
    agent_id = state.id

    job_name =
      case Map.get(state.cron_jobs, logical_id) do
        nil -> "jido_cron:#{agent_id}:#{inspect(logical_id)}"
        name -> name
      end

    _ = Jido.Scheduler.delete_job(String.to_atom(job_name))

    Logger.debug("AgentServer #{agent_id} cancelled cron job #{inspect(logical_id)}")

    new_state = %{state | cron_jobs: Map.delete(state.cron_jobs, logical_id)}

    {:ok, new_state}
  end
end
