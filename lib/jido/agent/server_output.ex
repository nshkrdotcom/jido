defmodule Jido.Agent.Server.Output do
  @moduledoc """
  Centralizes signal output for the Agent Server.

  Provides three output channels:
  - emit_out: Generic signal emission (out channel)
  - emit_log: Log message emission (log channel)
  - emit_err: Error message emission (err channel)
  """

  require Logger
  use ExDbug, enabled: true
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  alias Jido.Signal.Dispatch

  @doc """
  Emits a signal through the 'out' channel, optionally processing it through the agent's process_result callback.
  """
  @spec emit_out(%ServerState{}, term(), keyword()) :: :ok | {:error, term()}
  def emit_out(%ServerState{} = state, data, opts \\ []) do
    dbug("Emitting out signal", state: state, data: data, opts: opts)
    # Process data through agent callback if available
    processed_data =
      if state.agent && function_exported?(state.agent.__struct__, :process_result, 2) do
        dbug("Processing data through agent callback")
        state.agent.__struct__.process_result(state.agent, data)
      else
        dbug("No agent callback, using raw data")
        data
      end

    # Create a new signal with the processed data
    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.out",
        data: processed_data
      })

    dbug("Created out signal", signal: signal)

    # Emit the signal using the 'out' channel
    emit_signal(state, signal, Keyword.put(opts, :channel, :out))
  end

  @doc """
  Emits a log message as a signal through the 'log' channel.
  """
  @spec emit_log(%ServerState{}, atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def emit_log(%ServerState{} = state, level, message, opts \\ []) do
    dbug("Emitting log signal", state: state, level: level, message: message, opts: opts)

    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.log.#{level}",
        data: message
      })

    dbug("Created log signal", signal: signal)
    emit_signal(state, signal, Keyword.put(opts, :channel, :log))
  end

  @doc """
  Emits an error message as a signal through the 'err' channel.
  """
  @spec emit_err(%ServerState{}, String.t(), map(), keyword()) :: :ok | {:error, term()}
  def emit_err(%ServerState{} = state, message, metadata \\ %{}, opts \\ []) do
    dbug("Emitting error signal", state: state, message: message, metadata: metadata, opts: opts)

    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.error",
        data: %{
          message: message,
          metadata: metadata,
          agent_id: state.agent.id,
          timestamp: DateTime.utc_now()
        }
      })

    dbug("Created error signal", signal: signal)
    emit_signal(state, signal, Keyword.put(opts, :channel, :err))
  end

  @doc """
  Core signal emission function that handles dispatch configuration and delivery.
  Supports both single and multiple dispatch configurations.
  """
  @spec emit_signal(%ServerState{}, Signal.t(), keyword()) :: :ok | {:error, term()}
  def emit_signal(%ServerState{} = state, signal, opts \\ []) do
    dbug("Emitting signal", state: state, signal: signal, opts: opts)
    # Get the channel from opts or default to :out
    channel = Keyword.get(opts, :channel, :out)
    dbug("Using channel", channel: channel)

    # Get the dispatch config for the specified channel
    dispatch_config =
      case Keyword.get(opts, :dispatch) do
        nil -> get_in(state.output, [channel])
        config -> config
      end

    dbug("Using dispatch config", dispatch_config: dispatch_config)

    # Update signal with correlation and causation IDs, prioritizing:
    # 1. opts override
    # 2. existing signal values (if not nil)
    # 3. state values
    # 4. generate new UUIDs as last resort
    signal = %{
      signal
      | jido_correlation_id:
          Keyword.get(opts, :correlation_id) ||
            if(is_nil(signal.jido_correlation_id),
              do: state.current_correlation_id || UUID.uuid4(),
              else: signal.jido_correlation_id
            ),
        jido_causation_id:
          Keyword.get(opts, :causation_id) ||
            if(is_nil(signal.jido_causation_id),
              do: state.current_causation_id || UUID.uuid4(),
              else: signal.jido_causation_id
            )
    }

    dbug("Updated signal with IDs", signal: signal)

    # First handle any jido_output dispatch config from the signal
    if signal.jido_output do
      dbug("Processing jido_output dispatch config", jido_output: signal.jido_output)

      case signal.jido_output do
        dispatches when is_list(dispatches) ->
          dbug("Processing multiple jido_output dispatches", dispatches: dispatches)

          Enum.each(dispatches, fn {adapter, adapter_opts} ->
            do_dispatch(adapter, adapter_opts, signal)
          end)

        {adapter, adapter_opts} ->
          dbug("Processing single jido_output dispatch", adapter: adapter, opts: adapter_opts)
          do_dispatch(adapter, adapter_opts, signal)
      end
    end

    # Then handle the channel-based dispatch config
    case dispatch_config do
      # List of dispatches
      dispatches when is_list(dispatches) ->
        dbug("Processing multiple channel dispatches", dispatches: dispatches)
        # Dispatch to each configured adapter
        Enum.each(dispatches, fn
          {_key, {adapter, adapter_opts}} -> do_dispatch(adapter, adapter_opts, signal)
          {adapter, adapter_opts} -> do_dispatch(adapter, adapter_opts, signal)
        end)

      # Single dispatch
      {adapter, adapter_opts} ->
        dbug("Processing single channel dispatch", adapter: adapter, opts: adapter_opts)
        do_dispatch(adapter, adapter_opts, signal)
    end

    :ok
  end

  defp do_dispatch(Jido.Signal.Dispatch.NoopAdapter, opts, signal) do
    dbug("Dispatching to NoopAdapter", opts: opts, signal: signal)

    if test_pid = Process.get(:test_pid) do
      send(test_pid, {:dispatch, signal, opts})
    end
  end

  defp do_dispatch(adapter, adapter_opts, signal) do
    dbug("Dispatching to adapter", adapter: adapter, opts: adapter_opts, signal: signal)
    Dispatch.dispatch(signal, {adapter, adapter_opts})
  end
end
