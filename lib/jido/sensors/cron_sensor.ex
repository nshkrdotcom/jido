# defmodule Jido.Sensors.Cron do
#   @moduledoc """
#   A sensor that emits signals based on cron schedules.

#   This sensor supports:
#   - Multiple named schedules per sensor instance
#   - Runtime schedule management (add/remove/pause)
#   - Second-level granularity
#   - Timezone-aware scheduling
#   - Job status tracking
#   """
#   use Jido.Sensor

#   import Crontab.CronExpression
#   require Logger

#   @type schedule_config :: %{
#           name: atom(),
#           schedule: String.t(),
#           timezone: String.t(),
#           enabled: boolean(),
#           # Will hold task-specific config
#           task: map()
#         }

#   @impl true
#   def mount(opts) do
#     state = %{
#       bus_name: Keyword.fetch!(opts, :bus_name),
#       stream_id: Keyword.fetch!(opts, :stream_id),
#       # Map of name -> schedule_config
#       schedules: %{},
#       quantum_ref: opts[:quantum_ref] || :jido_quantum
#     }

#     # If initial schedules were provided, add them
#     schedules = Keyword.get(opts, :schedules, [])

#     state =
#       Enum.reduce(schedules, state, fn schedule, acc ->
#         case add_schedule(acc, schedule) do
#           {:ok, new_state} -> new_state
#           {:error, _} -> acc
#         end
#       end)

#     {:ok, state}
#   end

#   @impl true
#   def handle_event({:schedule_triggered, schedule_name}, state) do
#     schedule = get_in(state, [:schedules, schedule_name])

#     signal =
#       Jido.Signal.new(%{
#         source: "cron_sensor:#{schedule_name}",
#         subject: "cron_trigger",
#         type: "schedule",
#         data: %{
#           schedule: schedule.schedule,
#           timezone: schedule.timezone,
#           task: schedule.task,
#           triggered_at: DateTime.now!(schedule.timezone)
#         },
#         timestamp: DateTime.utc_now()
#       })

#     # Return signal with routing info
#     {:ok, {state.bus_name, state.stream_id}, signal}
#   end

#   # Public API for schedule management

#   @spec add_schedule(GenServer.server(), schedule_config()) ::
#           {:ok, schedule_name :: atom()} | {:error, term()}
#   def add_schedule(server, schedule_config) do
#     GenServer.call(server, {:add_schedule, schedule_config})
#   end

#   @spec remove_schedule(GenServer.server(), atom()) :: :ok | {:error, term()}
#   def remove_schedule(server, schedule_name) do
#     GenServer.call(server, {:remove_schedule, schedule_name})
#   end

#   @spec enable_schedule(GenServer.server(), atom()) :: :ok | {:error, term()}
#   def enable_schedule(server, schedule_name) do
#     GenServer.call(server, {:enable_schedule, schedule_name})
#   end

#   @spec disable_schedule(GenServer.server(), atom()) :: :ok | {:error, term()}
#   def disable_schedule(server, schedule_name) do
#     GenServer.call(server, {:disable_schedule, schedule_name})
#   end

#   @spec get_schedules(GenServer.server()) :: %{atom() => schedule_config()}
#   def get_schedules(server) do
#     GenServer.call(server, :get_schedules)
#   end

#   # GenServer callbacks for schedule management

#   @impl GenServer
#   def handle_call({:add_schedule, config}, _from, state) do
#     with {:ok, name} <- validate_name(config.name),
#          {:ok, cron} <- parse_schedule(config.schedule),
#          {:ok, _tz} <- validate_timezone(config.timezone) do
#       job =
#         Quantum.Job.new()
#         |> Quantum.Job.set_name(name)
#         |> Quantum.Job.set_schedule(cron)
#         |> Quantum.Job.set_timezone(config.timezone)
#         |> Quantum.Job.set_task(fn ->
#           send(self(), {:schedule_triggered, name})
#         end)
#         |> Quantum.Job.set_state(if config.enabled, do: :active, else: :inactive)

#       case Quantum.add_job(state.quantum_ref, job) do
#         :ok ->
#           new_state = put_in(state, [:schedules, name], config)
#           {:reply, {:ok, name}, new_state}

#         error ->
#           {:reply, error, state}
#       end
#     else
#       error -> {:reply, error, state}
#     end
#   end

#   def handle_call({:remove_schedule, name}, _from, state) do
#     case Quantum.delete_job(state.quantum_ref, name) do
#       :ok ->
#         new_state = update_in(state.schedules, &Map.delete(&1, name))
#         {:reply, :ok, new_state}

#       error ->
#         {:reply, error, state}
#     end
#   end

#   def handle_call({:enable_schedule, name}, _from, state) do
#     with :ok <- Quantum.activate_job(state.quantum_ref, name) do
#       new_state = update_in(state.schedules[name], &Map.put(&1, :enabled, true))
#       {:reply, :ok, new_state}
#     else
#       error -> {:reply, error, state}
#     end
#   end

#   def handle_call({:disable_schedule, name}, _from, state) do
#     with :ok <- Quantum.deactivate_job(state.quantum_ref, name) do
#       new_state = update_in(state.schedules[name], &Map.put(&1, :enabled, false))
#       {:reply, :ok, new_state}
#     else
#       error -> {:reply, error, state}
#     end
#   end

#   def handle_call(:get_schedules, _from, state) do
#     {:reply, state.schedules, state}
#   end

#   # Helper functions

#   defp validate_name(name) when is_atom(name), do: {:ok, name}
#   defp validate_name(_), do: {:error, :invalid_name}

#   defp parse_schedule(schedule) do
#     case Crontab.CronExpression.Parser.parse(schedule, true) do
#       {:ok, cron} -> {:ok, cron}
#       error -> {:error, {:invalid_schedule, error}}
#     end
#   end

#   defp validate_timezone(timezone) do
#     case DateTime.now(timezone) do
#       {:ok, _} -> {:ok, timezone}
#       {:error, reason} -> {:error, {:invalid_timezone, reason}}
#     end
#   end

#   # Cleanup on shutdown
#   @impl true
#   def terminate(_reason, state) do
#     Enum.each(state.schedules, fn {name, _} ->
#       Quantum.delete_job(state.quantum_ref, name)
#     end)
#   end
# end
