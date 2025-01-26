defmodule Jido.Signal.Dispatch do
  @moduledoc """
  Dispatch signals to the appropriate targets.

  Provides functionality to deliver signals to other processes using configurable adapters.
  Supports built-in adapters for common use cases and allows custom adapters for extensibility.
  """

  @type adapter :: :pid | :bus | :named | :pubsub | nil | module()

  @type dispatch_config :: {adapter(), Keyword.t()}

  @builtin_adapters %{
    pid: Jido.Signal.Dispatch.PidAdapter,
    bus: Jido.Signal.Dispatch.Bus,
    named: Jido.Signal.Dispatch.Named,
    pubsub: Jido.Signal.Dispatch.PubSub,
    nil: nil
  }

  @doc """
  Validates a dispatch configuration.

  ## Parameters

  - `config` - Dispatch configuration tuple containing:
    - adapter - Built-in adapter name or module implementing dispatch behavior
    - opts - Options passed to the adapter

  ## Returns

  - `{:ok, config}` if the configuration is valid
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      iex> config = {:pid, [target: {:pid, self()}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}
  """
  @spec validate_opts(dispatch_config()) :: {:ok, dispatch_config()} | {:error, term()}
  def validate_opts({nil, opts}) when is_list(opts) do
    {:ok, {nil, opts}}
  end

  def validate_opts({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    with {:ok, adapter_module} <- resolve_adapter(adapter),
         {:ok, validated_opts} <- adapter_module.validate_opts(opts) do
      {:ok, {adapter, validated_opts}}
    end
  end

  def validate_opts(_opts) do
    {:error, :invalid_dispatch_config}
  end

  @doc """
  Dispatches a signal using the provided configuration.

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Dispatch configuration tuple containing:
    - adapter - Built-in adapter name or module implementing dispatch behavior
    - opts - Options passed to the adapter

  ## Examples

      # Using built-in PID adapter
      iex> config = {:pid, [target: {:pid, pid}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Using built-in bus adapter
      iex> config = {:bus, [target: {:bus, :my_bus}, stream: "events"]}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Using custom adapter module
      iex> config = {MyApp.CustomAdapter, [custom_option: "value"]}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Using nil adapter (noop)
      iex> config = {:nil, []}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok
  """
  @spec dispatch(Jido.Signal.t(), dispatch_config()) :: :ok | {:ok, term()} | {:error, term()}
  def dispatch(_signal, {nil, _opts}), do: :ok

  def dispatch(signal, {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    with {:ok, adapter_module} <- resolve_adapter(adapter),
         {:ok, validated_opts} <- adapter_module.validate_opts(opts) do
      adapter_module.deliver(signal, validated_opts)
    end
  end

  def dispatch(_signal, _config) do
    {:error, :invalid_dispatch_config}
  end

  defp resolve_adapter(nil), do: {:error, :no_adapter_needed}

  defp resolve_adapter(adapter) when is_atom(adapter) do
    case Map.fetch(@builtin_adapters, adapter) do
      {:ok, module} when not is_nil(module) ->
        {:ok, module}

      {:ok, nil} ->
        {:error, :no_adapter_needed}

      :error ->
        if Code.ensure_loaded?(adapter) and function_exported?(adapter, :deliver, 2) do
          {:ok, adapter}
        else
          {:error,
           "#{inspect(adapter)} is not a valid adapter - must be :pid, :bus, :named or a module implementing deliver/2"}
        end
    end
  end
end
