defmodule Jido.Signal.Dispatch.NoopAdapter do
  @moduledoc """
  No-op implementation of signal dispatch that does nothing.
  """
  @behaviour Jido.Signal.Dispatch.Adapter

  @impl Jido.Signal.Dispatch.Adapter
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()}
  def validate_opts(opts), do: {:ok, opts}

  @impl Jido.Signal.Dispatch.Adapter
  @spec deliver(Jido.Signal.t(), Keyword.t()) :: :ok
  def deliver(_signal, _opts), do: :ok
end
