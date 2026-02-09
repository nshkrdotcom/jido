defmodule Jido.SystemTask do
  @moduledoc false

  @default_supervisor Jido.SystemTaskSupervisor

  @typedoc false
  @type async_task :: %{
          required(:__struct__) => Task,
          required(:mfa) => {module(), atom(), non_neg_integer()},
          required(:owner) => pid(),
          required(:pid) => pid() | atom() | port() | {atom(), atom()} | nil,
          required(:ref) => reference()
        }

  @doc false
  @spec async_nolink((-> term())) :: async_task()
  def async_nolink(fun) when is_function(fun, 0) do
    async_nolink(@default_supervisor, fun)
  end

  @doc false
  @spec async_nolink(term(), (-> term())) :: async_task()
  def async_nolink(task_supervisor, fun)
      when (is_atom(task_supervisor) or is_pid(task_supervisor)) and is_function(fun, 0) do
    Task.Supervisor.async_nolink(task_supervisor, fun)
  catch
    :exit, _reason ->
      Task.async(fun)
  end

  @doc false
  @spec start_child((-> term())) :: pid()
  def start_child(fun) when is_function(fun, 0) do
    start_child(@default_supervisor, fun)
  end

  @doc false
  @spec start_child(term(), (-> term())) :: pid()
  def start_child(task_supervisor, fun)
      when (is_atom(task_supervisor) or is_pid(task_supervisor)) and is_function(fun, 0) do
    case Task.Supervisor.start_child(task_supervisor, fun) do
      {:ok, pid} when is_pid(pid) ->
        pid

      {:error, _reason} ->
        spawn(fun)
    end
  catch
    :exit, _reason ->
      spawn(fun)
  end
end
