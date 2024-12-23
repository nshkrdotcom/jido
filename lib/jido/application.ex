defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Jido.Workflow.TaskSupervisor},
      {Registry, keys: :unique, name: Jido.AgentRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.AgentSupervisor}
    ]

    # Initialize discovery cache asynchronously
    Task.start(fn ->
      :ok = Jido.Discovery.init()
    end)

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.ApplicationSupervisor)
  end
end
