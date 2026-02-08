defmodule Jido.RuntimeDefaults do
  @moduledoc """
  Centralized runtime defaults for timeouts, limits, and supervisor guardrails.

  Values can be overridden via application config:

      config :jido, Jido.RuntimeDefaults,
        agent_server_call_timeout: 10_000,
        await_timeout: 10_000,
        plugin_hook_timeout: 1_000,
        max_agents: 10_000,
        max_tasks: 1_000,
        system_task_max_children: 2_000,
        worker_pool_timeout: 5_000,
        worker_pool_call_timeout: 5_000
  """

  @app :jido
  @config_key __MODULE__

  @agent_server_call_timeout 10_000
  @await_timeout 10_000
  @plugin_hook_timeout 1_000
  @hibernate_timeout 2_000
  @max_queue_size 10_000
  @max_agents 10_000
  @max_tasks 1_000
  @system_task_max_children 2_000
  @worker_pool_timeout 5_000
  @worker_pool_call_timeout 5_000

  @spec agent_server_call_timeout() :: pos_integer()
  def agent_server_call_timeout,
    do: get(:agent_server_call_timeout, @agent_server_call_timeout)

  @spec await_timeout() :: pos_integer()
  def await_timeout, do: get(:await_timeout, @await_timeout)

  @spec plugin_hook_timeout() :: pos_integer()
  def plugin_hook_timeout, do: get(:plugin_hook_timeout, @plugin_hook_timeout)

  @spec hibernate_timeout() :: pos_integer()
  def hibernate_timeout, do: get(:hibernate_timeout, @hibernate_timeout)

  @spec max_agents() :: pos_integer()
  def max_agents, do: get(:max_agents, @max_agents)

  @spec max_queue_size() :: pos_integer()
  def max_queue_size, do: get(:max_queue_size, @max_queue_size)

  @spec max_tasks() :: pos_integer()
  def max_tasks, do: get(:max_tasks, @max_tasks)

  @spec system_task_max_children() :: pos_integer()
  def system_task_max_children,
    do: get(:system_task_max_children, @system_task_max_children)

  @spec worker_pool_timeout() :: pos_integer()
  def worker_pool_timeout, do: get(:worker_pool_timeout, @worker_pool_timeout)

  @spec worker_pool_call_timeout() :: pos_integer()
  def worker_pool_call_timeout,
    do: get(:worker_pool_call_timeout, @worker_pool_call_timeout)

  defp get(key, default) do
    @app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(key, default)
  end
end
