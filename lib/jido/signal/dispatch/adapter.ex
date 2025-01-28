defmodule Jido.Signal.Dispatch.Adapter do
  @callback validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
  @callback deliver(Jido.Signal.t(), Keyword.t()) :: :ok | {:error, term()}
end
