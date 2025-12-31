defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Cron do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.Signal.CronTick

  def exec(
        %{cron: cron_expr, message: message, job_id: logical_id, timezone: tz},
        _input_signal,
        state
      ) do
    agent_id = state.id

    # Generate job_id if not provided
    logical_id = logical_id || make_ref()

    # Create unique job name scoped to agent
    job_name = job_name(agent_id, logical_id)

    # Build signal from message
    signal =
      case message do
        %Jido.Signal{} = s ->
          s

        other ->
          CronTick.new!(
            %{job_id: logical_id, message: other},
            source: "/agent/#{agent_id}"
          )
      end

    # Build Quantum job
    job =
      Jido.Scheduler.new_job()
      |> Quantum.Job.set_name(String.to_atom(job_name))
      |> Quantum.Job.set_schedule(parse_cron!(cron_expr))
      |> maybe_set_timezone(tz)
      |> Quantum.Job.set_task(fn ->
        # Fire signal into the agent (fire-and-forget)
        _ = Jido.AgentServer.cast(agent_id, signal)
        :ok
      end)

    # Upsert: delete previous job with same name (if exists), then add
    _ = Jido.Scheduler.delete_job(String.to_atom(job_name))
    :ok = Jido.Scheduler.add_job(job)

    Logger.debug(
      "AgentServer #{agent_id} registered cron job #{inspect(logical_id)}: #{cron_expr}"
    )

    # Track in state for cleanup
    new_state = put_in(state.cron_jobs[logical_id], job_name)

    {:ok, new_state}
  end

  defp job_name(agent_id, job_id) do
    "jido_cron:#{agent_id}:#{inspect(job_id)}"
  end

  defp parse_cron!(expr) when is_binary(expr) do
    Crontab.CronExpression.Parser.parse!(expr, true)
  end

  defp parse_cron!(%Crontab.CronExpression{} = expr), do: expr

  defp maybe_set_timezone(job, nil), do: job
  defp maybe_set_timezone(job, tz), do: Quantum.Job.set_timezone(job, tz)
end
