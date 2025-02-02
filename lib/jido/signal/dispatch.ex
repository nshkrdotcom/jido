defmodule Jido.Signal.Dispatch do
  @moduledoc """
  Dispatch signals to the appropriate targets.

  Provides functionality to deliver signals to other processes using configurable adapters.
  Supports built-in adapters for common use cases and allows custom adapters for extensibility.
  """

  @type adapter :: :pid | :bus | :named | :pubsub | nil | module()
  @type dispatch_config :: {adapter(), Keyword.t()}
  @type dispatch_configs :: dispatch_config() | [default: dispatch_config()] | keyword()

  @builtin_adapters %{
    pid: Jido.Signal.Dispatch.PidAdapter,
    bus: Jido.Signal.Dispatch.Bus,
    named: Jido.Signal.Dispatch.Named,
    pubsub: Jido.Signal.Dispatch.PubSub,
    logger: Jido.Signal.Dispatch.LoggerAdapter,
    console: Jido.Signal.Dispatch.ConsoleAdapter,
    noop: Jido.Signal.Dispatch.NoopAdapter,
    nil: nil
  }

  @doc """
  Validates a dispatch configuration.

  ## Parameters

  - `config` - Either a single dispatch configuration tuple or a keyword list of named configurations
    where at least one must be named :default

  ## Returns

  - `{:ok, config}` if the configuration is valid
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      # Single config (backward compatible)
      iex> config = {:pid, [target: {:pid, self()}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}

      # Multiple configs with default
      iex> config = [
      ...>   default: {:bus, [target: {:bus, :default}, stream: "events"]},
      ...>   audit: {:pubsub, [target: {:pubsub, :audit}, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}
  """
  @spec validate_opts(dispatch_configs()) :: {:ok, dispatch_configs()} | {:error, term()}
  # Handle single dispatcher config (backward compatibility)
  def validate_opts(config = {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    validate_single_config(config)
  end

  # Handle keyword list of dispatchers
  def validate_opts(configs) when is_list(configs) do
    with {:ok, _} <- validate_has_default(configs),
         {:ok, validated_configs} <- validate_all_configs(configs) do
      {:ok, validated_configs}
    end
  end

  def validate_opts(_), do: {:error, :invalid_dispatch_config}

  @doc """
  Dispatches a signal using the provided configuration.

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Either a single dispatch configuration tuple or a keyword list of named configurations

  ## Examples

      # Single destination (backward compatible)
      iex> config = {:pid, [target: {:pid, pid}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Multiple destinations
      iex> config = [
      ...>   default: {:bus, [target: {:bus, :default}, stream: "events"]},
      ...>   audit: {:pubsub, [target: {:pubsub, :audit}, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok
  """
  @spec dispatch(Jido.Signal.t(), dispatch_configs()) :: :ok | {:error, term()}
  # Handle single dispatcher (backward compatibility)
  def dispatch(signal, config = {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    dispatch_single(signal, config)
  end

  # Handle multiple dispatchers
  def dispatch(signal, configs) when is_list(configs) do
    results =
      Enum.map(configs, fn {_name, config} ->
        dispatch_single(signal, config)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  def dispatch(_signal, _config) do
    {:error, :invalid_dispatch_config}
  end

  # Private helpers

  defp validate_has_default(configs) do
    if Keyword.has_key?(configs, :default) do
      {:ok, configs}
    else
      {:error, :missing_default_dispatcher}
    end
  end

  defp validate_all_configs(configs) do
    results =
      Enum.map(configs, fn {name, config} ->
        case validate_single_config(config) do
          {:ok, validated_config} -> {:ok, {name, validated_config}}
          error -> error
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, value} -> value end)}
      error -> error
    end
  end

  defp validate_single_config({nil, opts}) when is_list(opts) do
    {:ok, {nil, opts}}
  end

  defp validate_single_config({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    with {:ok, adapter_module} <- resolve_adapter(adapter),
         {:ok, validated_opts} <- adapter_module.validate_opts(opts) do
      {:ok, {adapter, validated_opts}}
    end
  end

  defp dispatch_single(_signal, {nil, _opts}), do: :ok

  defp dispatch_single(signal, {adapter, opts}) do
    with {:ok, adapter_module} <- resolve_adapter(adapter),
         {:ok, validated_opts} <- adapter_module.validate_opts(opts) do
      adapter_module.deliver(signal, validated_opts)
    end
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
