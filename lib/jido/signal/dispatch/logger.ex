defmodule Jido.Signal.Dispatch.LoggerAdapter do
  @moduledoc """
  Logger implementation of signal dispatch that logs signals using Elixir's Logger.
  Respects configured log levels and provides structured logging output.
  """
  @behaviour Jido.Signal.Dispatch.Adapter
  require Logger

  @valid_levels [:debug, :info, :warn, :error]

  @impl Jido.Signal.Dispatch.Adapter
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, String.t()}
  def validate_opts(opts) do
    level = Keyword.get(opts, :level, :info)

    if level in @valid_levels do
      {:ok, opts}
    else
      {:error, "Invalid log level: #{inspect(level)}. Must be one of #{inspect(@valid_levels)}"}
    end
  end

  @impl Jido.Signal.Dispatch.Adapter
  @spec deliver(Jido.Signal.t(), Keyword.t()) :: :ok
  def deliver(signal, opts) do
    level = Keyword.get(opts, :level, :info)
    structured = Keyword.get(opts, :structured, false)

    metadata = [
      source: signal.source,
      correlation_id: signal.jido_correlation_id,
      causation_id: signal.jido_causation_id
    ]

    if structured do
      Logger.log(
        level,
        fn ->
          %{
            event: "signal_dispatched",
            type: signal.type,
            metadata: signal.jido_metadata,
            data: signal.data,
            source: signal.source
          }
        end,
        metadata
      )
    else
      Logger.log(
        level,
        "Signal dispatched: #{signal.type} from #{signal.source} with data=#{inspect(signal.data)}",
        metadata
      )
    end

    :ok
  end
end
