defmodule JidoTest.CronSensorTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  import Crontab.CronExpression, only: [sigil_e: 2]

  alias Jido.CronSensor
  alias Jido.Signal

  @moduletag :capture_log

  setup do
    {:ok, test_pid: self()}
  end

  describe "CronSensor integration with Quantum" do
    test "adds and executes a scheduled job", %{test_pid: test_pid} do
      capture_log(fn ->
        {:ok, sensor_pid} =
          CronSensor.start_link(
            id: "test_cron_sensor",
            target: {:pid, target: test_pid},
            scheduler: Jido.Scheduler
          )

        schedule = ~e"* * * * * *"e
        :ok = CronSensor.add_job(sensor_pid, :test_job, schedule, :dummy_task)

        # Reduced timeout from 2000 to 1000ms
        assert_receive {:signal, {:ok, %Signal{} = signal}}, 1_000
        assert signal.type == "cron_trigger"
        assert signal.data.name == :test_job
        # Cleanup
        :ok = CronSensor.remove_job(sensor_pid, :test_job)
      end)
    end

    test "can specify multiple jobs at startup", %{test_pid: test_pid} do
      capture_log(fn ->
        # Pass multiple job specs to 'jobs' param
        # 1) Autonamed (with 1-second schedule)
        # 2) Named job (with 1-second schedule)
        {:ok, sensor_pid} =
          CronSensor.start_link(
            id: "multi_cron_sensor",
            target: {:pid, target: test_pid},
            scheduler: Jido.Scheduler,
            jobs: [
              # auto-named
              {~e"* * * * * *"e, :auto_task},
              # manual named
              {:named_job, ~e"* * * * * *"e, :named_task}
            ]
          )

        # Reduced timeout from 2000 to 1000ms
        signals =
          for _ <- 1..2 do
            receive do
              {:signal, {:ok, %Signal{} = s}} -> s
            after
              1_000 -> flunk("Did not receive signals from multi job in time")
            end
          end

        # Just confirm they are from the sensor and have type "cron_trigger"
        Enum.each(signals, fn s ->
          assert s.type == "cron_trigger"
        end)

        # We won't know the name for the auto-named job, but at least one should have data.name == :named_job
        assert Enum.any?(signals, fn s -> s.data.name == :named_job end)

        # Cleanup the named job (we can't cleanup the auto-named one since we don't know its name)
        :ok = CronSensor.remove_job(sensor_pid, :named_job)
      end)
    end

    test "runs job immediately on demand", %{test_pid: test_pid} do
      capture_log(fn ->
        {:ok, sensor_pid} =
          CronSensor.start_link(
            id: "test_cron_sensor_immediate",
            target: {:pid, target: test_pid},
            scheduler: Jido.Scheduler
          )

        # something that won't trigger soon
        schedule = ~e"0 0 * * *"e
        :ok = CronSensor.add_job(sensor_pid, :immediate_job, schedule, :dummy_task)

        :ok = CronSensor.run_job(sensor_pid, :immediate_job)
        # Reduced timeout from 1000 to 500ms since this is immediate
        assert_receive {:signal, {:ok, %Signal{} = signal}}, 500
        assert signal.type == "cron_trigger"
        assert signal.data.name == :immediate_job
        # Cleanup
        :ok = CronSensor.remove_job(sensor_pid, :immediate_job)
      end)
    end

    test "activate/deactivate a job", %{test_pid: test_pid} do
      capture_log(fn ->
        {:ok, sensor_pid} =
          CronSensor.start_link(
            id: "test_cron_sensor_toggle",
            target: {:pid, target: test_pid},
            scheduler: Jido.Scheduler
          )

        schedule = ~e"* * * * * *"e
        :ok = CronSensor.add_job(sensor_pid, :toggle_job, schedule, :dummy_task)
        # Deactivate it
        :ok = CronSensor.deactivate_job(sensor_pid, :toggle_job)
        # Reduced timeout from 1500 to 750ms
        refute_receive {:signal, {:ok, _}}, 750

        # Activate it
        :ok = CronSensor.activate_job(sensor_pid, :toggle_job)
        # Reduced timeout from 1500 to 750ms
        assert_receive {:signal, {:ok, %Signal{} = _signal}}, 750

        # Cleanup
        :ok = CronSensor.remove_job(sensor_pid, :toggle_job)
      end)
    end
  end
end
