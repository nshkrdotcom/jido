defmodule Jido.Signal.Dispatch.Bus do
  @behaviour Jido.Signal.Dispatch.Adapter

  @type delivery_target :: atom()
  @type delivery_opts :: [
          target: delivery_target(),
          stream: String.t()
        ]
  @type delivery_error ::
          :bus_not_found
          | term()

  @impl Jido.Signal.Dispatch.Adapter
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
  def validate_opts(opts) do
    with {:ok, target} <- validate_target(Keyword.get(opts, :target)),
         {:ok, stream} <- validate_stream(Keyword.get(opts, :stream, "default")) do
      {:ok,
       opts
       |> Keyword.put(:target, target)
       |> Keyword.put(:stream, stream)}
    end
  end

  @impl Jido.Signal.Dispatch.Adapter
  @spec deliver(Jido.Signal.t(), delivery_opts()) ::
          :ok | {:error, delivery_error()}
  def deliver(signal, opts) do
    bus_name = Keyword.fetch!(opts, :target)
    stream = Keyword.fetch!(opts, :stream)

    case Jido.Bus.whereis(bus_name) do
      {:ok, _pid} ->
        Jido.Bus.publish(bus_name, stream, :any_version, [signal])

      {:error, :not_found} ->
        {:error, :bus_not_found}
    end
  end

  defp validate_target(name) when is_atom(name), do: {:ok, name}
  defp validate_target(_), do: {:error, "target must be a bus name atom"}

  defp validate_stream(stream) when is_binary(stream), do: {:ok, stream}
  defp validate_stream(_), do: {:error, "stream must be a string"}
end
