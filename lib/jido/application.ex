defmodule Jido.Application do
  @moduledoc false
  use Application

  @doc false
  def start(_type, _args) do
    children = [
      # Telemetry handler for agent and strategy metrics
      Jido.Telemetry,
      # Global supervisor for internal framework background tasks
      {Task.Supervisor, name: Jido.SystemTaskSupervisor}
    ]

    # Register essential signal extensions before starting supervision tree
    register_signal_extensions()

    case Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor) do
      {:ok, pid} ->
        # Initialize discovery catalog asynchronously (fire-and-forget)
        Jido.Discovery.init_async()
        {:ok, pid}

      other ->
        other
    end
  end

  # Ensure critical signal extensions are registered
  defp register_signal_extensions do
    extensions = [
      Jido.Signal.Ext.Trace,
      Jido.Signal.Ext.Dispatch,
      Jido.Signal.Ext.Target
    ]

    for ext <- extensions do
      Code.ensure_loaded(ext)
      Jido.Signal.Ext.Registry.register(ext)
    end

    :ok
  rescue
    # Gracefully handle missing modules during compilation or testing
    _ -> :ok
  end
end
