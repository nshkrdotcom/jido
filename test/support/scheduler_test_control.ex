defmodule JidoTest.Support.SchedulerTestControl do
  @moduledoc false

  import JidoTest.Eventually

  alias Jido.AgentServer

  def force_tick(job_pid, opts \\ []) when is_pid(job_pid) do
    force_job_timer(job_pid, :tick, opts)
  end

  def force_retry(job_pid, opts \\ []) when is_pid(job_pid) do
    force_job_timer(job_pid, :retry_schedule, opts)
  end

  def force_cron_restart(server_pid, logical_id, opts \\ []) when is_pid(server_pid) do
    eventually(
      fn ->
        case AgentServer.state(server_pid) do
          {:ok, state} ->
            case Map.get(state.cron_restart_timers, logical_id) do
              timer_ref when is_reference(timer_ref) ->
                send(server_pid, {:timeout, timer_ref, {:cron_restart, logical_id}})
                true

              _other ->
                false
            end

          _other ->
            false
        end
      end,
      opts
    )
  end

  defp force_job_timer(job_pid, timer_kind, opts) do
    eventually(
      fn ->
        case :sys.get_state(job_pid) do
          %{timer_ref: timer_ref, retrying?: retrying?} when is_reference(timer_ref) ->
            if current_timer_kind(retrying?) == timer_kind do
              send(job_pid, {:timeout, timer_ref, timer_kind})
              true
            else
              false
            end

          _other ->
            false
        end
      end,
      opts
    )
  end

  defp current_timer_kind(true), do: :retry_schedule
  defp current_timer_kind(false), do: :tick
end
