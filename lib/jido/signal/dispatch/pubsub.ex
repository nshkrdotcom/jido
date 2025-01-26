defmodule Jido.Signal.Dispatch.PubSub do
  @behaviour Jido.Signal.Dispatch.Adapter

  @type delivery_target :: {:pubsub, atom()}
  @type delivery_opts :: [
          target: delivery_target(),
          topic: String.t()
        ]
  @type delivery_error ::
          :pubsub_not_found
          | term()

  @impl Jido.Signal.Dispatch.Adapter
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
  def validate_opts(opts) do
    with {:ok, target} <- validate_target(Keyword.get(opts, :target)),
         {:ok, topic} <- validate_topic(Keyword.get(opts, :topic)) do
      {:ok,
       opts
       |> Keyword.put(:target, target)
       |> Keyword.put(:topic, topic)}
    end
  end

  @impl Jido.Signal.Dispatch.Adapter
  @spec deliver(Jido.Signal.t(), delivery_opts()) ::
          :ok | {:error, delivery_error()}
  def deliver(signal, opts) do
    target = Keyword.fetch!(opts, :target)
    topic = Keyword.fetch!(opts, :topic)

    case target do
      {:pubsub, pubsub_name} ->
        try do
          Phoenix.PubSub.broadcast(pubsub_name, topic, signal)
          :ok
        catch
          :exit, {:noproc, _} -> {:error, :pubsub_not_found}
          :exit, reason -> {:error, reason}
        end
    end
  end

  defp validate_target({:pubsub, name}) when is_atom(name), do: {:ok, {:pubsub, name}}
  defp validate_target(_), do: {:error, "invalid target: must be {:pubsub, name}"}

  defp validate_topic(topic) when is_binary(topic), do: {:ok, topic}
  defp validate_topic(_), do: {:error, "topic must be a string"}
end
