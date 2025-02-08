defmodule Jido.Signal.Dispatch do
  @moduledoc """
  A flexible signal dispatching system that routes signals to various destinations using configurable adapters.

  The Dispatch module serves as the central hub for signal delivery in the Jido system. It provides a unified
  interface for sending signals to different destinations through various adapters. Each adapter implements
  specific delivery mechanisms suited for different use cases.

  ## Built-in Adapters

  The following adapters are provided out of the box:

  * `:pid` - Direct delivery to a specific process (see `Jido.Signal.Dispatch.PidAdapter`)
  * `:bus` - Delivery to an event bus (see `Jido.Signal.Dispatch.Bus`)
  * `:named` - Delivery to a named process (see `Jido.Signal.Dispatch.Named`)
  * `:pubsub` - Delivery via PubSub mechanism (see `Jido.Signal.Dispatch.PubSub`)
  * `:logger` - Log signals using Logger (see `Jido.Signal.Dispatch.LoggerAdapter`)
  * `:console` - Print signals to console (see `Jido.Signal.Dispatch.ConsoleAdapter`)
  * `:noop` - No-op adapter for testing/development (see `Jido.Signal.Dispatch.NoopAdapter`)

  ## Configuration

  Each adapter requires specific configuration options. A dispatch configuration is a tuple of
  `{adapter_type, options}` where:

  * `adapter_type` - One of the built-in adapter types above or a custom module implementing the `Jido.Signal.Dispatch.Adapter` behaviour
  * `options` - Keyword list of options specific to the chosen adapter

  Multiple dispatch configurations can be provided as a list to send signals to multiple destinations.

  ## Examples

      # Send to a specific PID
      config = {:pid, [target: {:pid, destination_pid}, delivery_mode: :async]}
      Jido.Signal.Dispatch.dispatch(signal, config)

      # Send to multiple destinations
      config = [
        {:bus, [target: {:bus, :default}, stream: "events"]},
        {:logger, [level: :info]},
        {:pubsub, [target: :audit, topic: "audit"]}
      ]
      Jido.Signal.Dispatch.dispatch(signal, config)

      # Using a custom adapter
      config = {MyCustomAdapter, [custom_option: "value"]}
      Jido.Signal.Dispatch.dispatch(signal, config)

  ## Custom Adapters

  To implement a custom adapter, create a module that implements the `Jido.Signal.Dispatch.Adapter`
  behaviour. The module must implement:

  * `validate_opts/1` - Validates the adapter-specific options
  * `deliver/2` - Handles the actual signal delivery

  See `Jido.Signal.Dispatch.Adapter` for more details.
  """

  @type adapter :: :pid | :bus | :named | :pubsub | :logger | :console | :noop | nil | module()
  @type dispatch_config :: {adapter(), Keyword.t()}
  @type dispatch_configs :: dispatch_config() | [dispatch_config()]

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

  - `config` - Either a single dispatch configuration tuple or a list of dispatch configurations

  ## Returns

  - `{:ok, config}` if the configuration is valid
  - `{:error, reason}` if the configuration is invalid

  ## Examples

      # Single config
      iex> config = {:pid, [target: {:pid, self()}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}

      # Multiple configs
      iex> config = [
      ...>   {:bus, [target: {:bus, :default}, stream: "events"]},
      ...>   {:pubsub, [target: {:pubsub, :audit}, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.validate_opts(config)
      {:ok, ^config}
  """
  @spec validate_opts(dispatch_configs()) :: {:ok, dispatch_configs()} | {:error, term()}
  # Handle single dispatcher config
  def validate_opts(config = {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    validate_single_config(config)
  end

  # Handle list of dispatchers
  def validate_opts(configs) when is_list(configs) do
    results = Enum.map(configs, &validate_single_config/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, value} -> value end)}
      error -> error
    end
  end

  def validate_opts(_), do: {:error, :invalid_dispatch_config}

  @doc """
  Dispatches a signal using the provided configuration.

  ## Parameters

  - `signal` - The signal to dispatch
  - `config` - Either a single dispatch configuration tuple or a list of configurations

  ## Examples

      # Single destination
      iex> config = {:pid, [target: {:pid, pid}, delivery_mode: :async]}
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok

      # Multiple destinations
      iex> config = [
      ...>   {:bus, [target: {:bus, :default}, stream: "events"]},
      ...>   {:pubsub, [target: :audit, topic: "audit"]}
      ...> ]
      iex> Jido.Signal.Dispatch.dispatch(signal, config)
      :ok
  """
  @spec dispatch(Jido.Signal.t(), dispatch_configs()) :: :ok | {:error, term()}
  # Handle single dispatcher
  def dispatch(signal, config = {adapter, opts}) when is_atom(adapter) and is_list(opts) do
    dispatch_single(signal, config)
  end

  # Handle multiple dispatchers
  def dispatch(signal, configs) when is_list(configs) do
    results = Enum.map(configs, &dispatch_single(signal, &1))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  def dispatch(_signal, _config) do
    {:error, :invalid_dispatch_config}
  end

  # Private helpers

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
