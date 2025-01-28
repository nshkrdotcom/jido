defmodule Jido.Agent.Server.Output do
  @moduledoc """
  Centralizes log/console output and event emission for the Agent Server.

  This module provides functions for:
  - Logging with correlation/causation IDs
  - Event emission with consistent metadata
  - Capturing operation results
  - Controlling output verbosity
  """

  require Logger
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Signal
  alias Jido.Signal.Dispatch

  @doc """
  Emits an event with consistent logging and metadata handling.
  """
  @spec emit_event(ServerState.t(), String.t(), map()) :: :ok | {:ok, term()} | {:error, term()}
  def emit_event(%ServerState{} = state, event_type, payload \\ %{}) do
    # Add correlation metadata
    set_logger_metadata(state)

    # Log if verbose level is info or lower
    log_message(state, :debug, "Emitting event #{event_type} with payload=#{inspect(payload)}")

    with {:ok, signal} <- ServerSignal.build_event(state, event_type, payload) do
      dispatch(state, signal)
    end
  end

  @doc """
  Emits a command with consistent logging and metadata handling.
  """
  @spec emit_cmd(ServerState.t(), term(), map(), Keyword.t()) ::
          :ok | {:ok, term()} | {:error, term()}
  def emit_cmd(%ServerState{} = state, instruction, params \\ %{}, opts \\ []) do
    set_logger_metadata(state)

    log_message(
      state,
      :info,
      "Emitting command #{inspect(instruction)} with params=#{inspect(params)}"
    )

    with {:ok, signal} <- ServerSignal.build_cmd(state, instruction, params, opts) do
      dispatch(state, signal)
    end
  end

  @doc """
  Emits a directive with consistent logging and metadata handling.
  """
  @spec emit_directive(ServerState.t(), struct()) :: :ok | {:ok, term()} | {:error, term()}
  def emit_directive(%ServerState{} = state, directive) do
    set_logger_metadata(state)

    log_message(state, :info, "Emitting directive #{inspect(directive)}")

    with {:ok, signal} <- ServerSignal.build_directive(state, directive) do
      dispatch(state, signal)
    end
  end

  @doc """
  Logs a message with consistent metadata handling and verbosity control.
  """
  @spec log_message(ServerState.t(), atom(), String.t() | map()) :: :ok
  def log_message(%ServerState{verbose: level} = state, msg_level, msg) do
    # Only log if message level is equal or higher priority than verbose setting
    if should_log?(level, msg_level) do
      set_logger_metadata(state)
      Logger.log(msg_level, msg)
    end

    :ok
  end

  @doc """
  Captures the result of an operation, logging appropriately based on success/failure.
  """
  @spec capture_result(ServerState.t(), any()) :: {:ok, ServerState.t()} | {:error, term()}
  def capture_result(state, result) do
    case result do
      {:ok, data} ->
        log_message(state, :info, "Successfully executed with data=#{inspect(data)}")
        {:ok, state}

      {:error, reason} ->
        log_message(state, :error, "Execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Helper to set logger metadata with correlation IDs from state.
  """
  @spec set_logger_metadata(ServerState.t()) :: :ok
  def set_logger_metadata(%ServerState{} = state) do
    metadata = [
      agent_id: state.agent.id,
      correlation_id: Map.get(state, :correlation_id),
      causation_id: Map.get(state, :causation_id)
    ]

    Logger.metadata(metadata)
    :ok
  end

  @doc """
  Helper macro for executing a block with logger metadata set.
  """
  defmacro with_logger_metadata(state, do: block) do
    quote do
      require Logger
      Jido.Agent.Server.Output.set_logger_metadata(unquote(state))
      result = unquote(block)
      Logger.reset_metadata()
      result
    end
  end

  defp dispatch(%{dispatch: {adapter, opts}}, %Signal{} = signal) do
    Dispatch.dispatch(signal, {adapter, opts})
  end

  # Helper to determine if a message should be logged based on verbosity levels
  defp should_log?(verbose_level, msg_level) do
    level_priority = %{
      debug: 0,
      info: 1,
      warn: 2,
      error: 3
    }

    cond do
      verbose_level == true -> true
      is_atom(verbose_level) -> level_priority[msg_level] >= level_priority[verbose_level]
      true -> false
    end
  end
end
