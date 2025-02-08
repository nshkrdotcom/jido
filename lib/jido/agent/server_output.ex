defmodule Jido.Agent.Server.Output do
  use ExDbug, enabled: false
  alias Jido.Signal
  alias Jido.Signal.Dispatch

  @default_dispatch {:logger, []}

  def emit(signal, opts \\ [])

  def emit(nil, _opts) do
    dbug("No signal provided")
    {:error, :no_signal}
  end

  def emit(%Signal{} = signal, opts) do
    dispatch_config =
      Keyword.get(opts, :dispatch) || signal.jido_dispatch || @default_dispatch

    dbug("Emitting", signal: signal, opts: opts)
    dbug("Using dispatch config", dispatch_config: dispatch_config)

    Dispatch.dispatch(signal, dispatch_config)
  end

  def emit(_invalid, _opts) do
    {:error, :invalid_signal}
  end
end
