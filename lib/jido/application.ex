defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Jido.Workflow.TaskSupervisor},
      {Registry, keys: :unique, name: Jido.AgentRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.AgentSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.ApplicationSupervisor)
  end
end
