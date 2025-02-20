defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Workflow Async Actions Task Supervisor
      {Task.Supervisor, name: Jido.Workflow.TaskSupervisor},

      # Default PubSub
      {Phoenix.PubSub, name: Jido.PubSub},

      # Agent Registry & Default Supervisor
      {Registry, keys: :unique, name: Jido.Agent.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.Agent.Supervisor},

      # Bus Registry & Default Supervisor
      {Registry, keys: :unique, name: Jido.Bus.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.Bus.Supervisor},

      # Add the Jido Scheduler (Quantum) under the name :jido_quantum
      {Jido.Scheduler, name: :jido_quantum}
    ]

    # Initialize discovery cache asynchronously
    Task.start(fn ->
      :ok = Jido.Discovery.init()
    end)

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end
end
