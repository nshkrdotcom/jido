defmodule Jido.Signal.Dispatch.Named do
  @behaviour Jido.Signal.Dispatch.Adapter

  @type delivery_target :: {:name, atom()}
  @type delivery_mode :: :sync | :async
  @type message_format :: (Jido.Signal.t() -> term())
  @type delivery_opts :: [
          target: delivery_target(),
          delivery_mode: delivery_mode(),
          timeout: timeout(),
          message_format: message_format()
        ]
  @type delivery_error ::
          :process_not_found
          | :process_not_alive
          | :timeout
          | term()

  @impl Jido.Signal.Dispatch.Adapter
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, term()}
  def validate_opts(opts) do
    with {:ok, target} <- validate_target(Keyword.get(opts, :target)),
         {:ok, mode} <- validate_mode(Keyword.get(opts, :delivery_mode, :async)) do
      {:ok,
       opts
       |> Keyword.put(:target, target)
       |> Keyword.put(:delivery_mode, mode)}
    end
  end

  defp validate_target({:name, name}) when is_atom(name), do: {:ok, {:name, name}}
  defp validate_target(_), do: {:error, :invalid_target}

  defp validate_mode(mode) when mode in [:sync, :async], do: {:ok, mode}
  defp validate_mode(_), do: {:error, :invalid_delivery_mode}

  @impl Jido.Signal.Dispatch.Adapter
  @spec deliver(Jido.Signal.t(), delivery_opts()) ::
          :ok | {:ok, term()} | {:error, delivery_error()}
  def deliver(signal, opts) do
    target = Keyword.fetch!(opts, :target)
    mode = Keyword.fetch!(opts, :delivery_mode)
    timeout = Keyword.get(opts, :timeout, 5000)
    message_format = Keyword.get(opts, :message_format, &default_message_format/1)

    case {target, mode} do
      {{:name, name}, :async} ->
        case Process.whereis(name) do
          nil ->
            {:error, :process_not_found}

          pid ->
            if Process.alive?(pid) do
              send(pid, message_format.(signal))
              :ok
            else
              {:error, :process_not_alive}
            end
        end

      {{:name, name}, :sync} ->
        case Process.whereis(name) do
          nil ->
            {:error, :process_not_found}

          pid ->
            if Process.alive?(pid) do
              try do
                message = message_format.(signal)
                GenServer.call(pid, message, timeout)
              catch
                :exit, {:timeout, _} -> {:error, :timeout}
                :exit, {:noproc, _} -> {:error, :process_not_alive}
                :exit, reason -> {:error, reason}
              end
            else
              {:error, :process_not_alive}
            end
        end
    end
  end

  defp default_message_format(signal), do: {:signal, signal}
end
