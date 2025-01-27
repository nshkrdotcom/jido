defmodule Jido.Signal.Dispatch.ConsoleAdapter do
  @moduledoc """
  Console implementation of signal dispatch that prints signals directly to stdout.
  Useful for interactive IEx sessions and direct console output.
  """
  @behaviour Jido.Signal.Dispatch.Adapter

  @impl Jido.Signal.Dispatch.Adapter
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()}
  def validate_opts(opts) do
    # No special validation needed for console adapter
    {:ok, opts}
  end

  @impl Jido.Signal.Dispatch.Adapter
  @spec deliver(Jido.Signal.t(), Keyword.t()) :: :ok
  def deliver(signal, _opts) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    IO.puts("""
    [#{timestamp}] SIGNAL DISPATCHED
    type=#{signal.type}
    source=#{signal.source}
    correlation_id=#{signal.correlation_id || "-"}
    causation_id=#{signal.causation_id || "-"}
    metadata=#{inspect(signal.metadata, pretty: true)}
    payload=#{inspect(signal.payload, pretty: true)}
    """)

    :ok
  end
end
