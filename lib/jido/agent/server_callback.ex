defmodule Jido.Agent.Server.Callback do
  @moduledoc """
  Manages callback invocations for Agent Server, providing a consistent interface
  for calling agent callbacks with proper error handling.

  This module handles:
  - Lifecycle callbacks (mount, code_change, shutdown)
  - Signal handling through agents and skills
  - Result processing through agents and skills

  All callbacks are called with proper error handling and propagation.
  """

  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  require OK

  @doc """
  Calls the mount callback on the agent if it exists.

  The mount callback is called when the agent server starts up and allows the agent
  to perform any necessary initialization.

  ## Parameters
    - state: The current server state containing the agent

  ## Returns
    - `{:ok, state}` - Mount successful with possibly modified state
    - `{:error, reason}` - Mount failed with reason
  """
  @spec mount(state :: ServerState.t()) :: {:ok, ServerState.t()} | {:error, term()}
  def mount(%ServerState{agent: agent} = state) do
    case agent.__struct__.mount(state, []) do
      {:ok, new_state} -> {:ok, new_state}
      error -> error
    end
  end

  @doc """
  Calls the code_change callback on the agent if it exists.

  The code_change callback is called when the agent's code is updated during a hot code upgrade.

  ## Parameters
    - state: The current server state containing the agent
    - old_vsn: The version being upgraded from
    - extra: Additional data passed to the upgrade

  ## Returns
    - `{:ok, state}` - Code change successful with possibly modified state
    - `{:error, reason}` - Code change failed with reason
  """
  @spec code_change(state :: ServerState.t(), old_vsn :: term(), extra :: term()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def code_change(%ServerState{agent: agent} = state, old_vsn, extra) do
    case agent.__struct__.code_change(state, old_vsn, extra) do
      {:ok, new_state} -> {:ok, new_state}
      error -> error
    end
  end

  @doc """
  Calls the shutdown callback on the agent if it exists.

  The shutdown callback is called when the agent server is stopping and allows the agent
  to perform any necessary cleanup.

  ## Parameters
    - state: The current server state containing the agent
    - reason: The reason for shutdown

  ## Returns
    - `{:ok, state}` - Shutdown successful with possibly modified state
    - `{:error, reason}` - Shutdown failed with reason
  """
  @spec shutdown(state :: ServerState.t(), reason :: term()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def shutdown(%ServerState{agent: agent} = state, reason) do
    case agent.__struct__.shutdown(state, reason) do
      {:ok, new_state} -> {:ok, new_state}
      error -> error
    end
  end

  @doc """
  Calls the handle_signal callback on the agent and all matching skills.

  The signal is first processed by the agent, then by any skills whose patterns
  match the signal type. Each handler can modify the signal before passing it
  to the next handler.

  ## Parameters
    - state: The current server state containing the agent and skills
    - signal: The signal to handle, or {:ok, signal} tuple

  ## Returns
    - `{:ok, signal}` - Signal successfully handled with possibly modified signal
    - `{:error, reason}` - Signal handling failed with reason
  """
  @spec handle_signal(state :: ServerState.t(), signal :: Signal.t() | {:ok, Signal.t()}) ::
          {:ok, Signal.t()} | {:error, term()}
  def handle_signal(state, {:ok, signal}), do: handle_signal(state, signal)

  def handle_signal(%ServerState{agent: agent, skills: skills} = _state, %Signal{} = signal) do
    # First let the agent handle the signal
    with {:ok, handled_signal} <- agent.__struct__.handle_signal(signal) do
      # Then let matching skills handle it
      matching_skills = find_matching_skills(skills, signal)

      Enum.reduce_while(matching_skills, {:ok, handled_signal}, fn {_key, skill},
                                                                   {:ok, acc_signal} ->
        case skill.__struct__.handle_signal(acc_signal) do
          {:ok, new_signal} -> {:cont, {:ok, new_signal}}
          error -> {:halt, error}
        end
      end)
    end
  end

  @doc """
  Calls the process_result callback on the agent and all matching skills.

  The result is first processed by the agent, then by any skills whose patterns
  match the signal type. Each handler can modify the result before passing it
  to the next handler.

  ## Parameters
    - state: The current server state containing the agent and skills
    - signal: The signal that produced the result
    - result: The result to process

  ## Returns
    - `{:ok, result}` - Result successfully processed with possibly modified result
    - `{:error, reason}` - Result processing failed with reason
  """
  @spec process_result(
          state :: ServerState.t(),
          signal :: Signal.t() | {:ok, Signal.t()},
          result :: term()
        ) :: {:ok, term()} | {:error, term()}
  def process_result(state, {:ok, signal}, result), do: process_result(state, signal, result)

  def process_result(
        %ServerState{agent: agent, skills: skills} = _state,
        %Signal{} = signal,
        result
      ) do
    # First let the agent process the result
    with {:ok, processed_result} <- agent.__struct__.process_result(signal, result) do
      # Then let matching skills process it
      matching_skills = find_matching_skills(skills, signal)

      Enum.reduce_while(matching_skills, {:ok, processed_result}, fn {_key, skill},
                                                                     {:ok, acc_result} ->
        case skill.__struct__.process_result(signal, acc_result) do
          {:ok, new_result} -> {:cont, {:ok, new_result}}
          error -> {:halt, error}
        end
      end)
    end
  end

  # Finds skills that match a signal's type based on their input/output patterns.
  #
  # Parameters:
  #   - skills: Map of skills to check
  #   - signal: Signal to match against
  #
  # Returns:
  #   List of {key, skill} tuples for matching skills
  @spec find_matching_skills(skills :: %{optional(atom()) => struct()}, signal :: Signal.t()) ::
          list({atom(), struct()})
  defp find_matching_skills(skills, %Signal{} = signal) do
    Enum.filter(skills, fn {_key, skill} ->
      patterns = skill.__struct__.signals()
      input_patterns = patterns[:input] || []
      output_patterns = patterns[:output] || []
      all_patterns = input_patterns ++ output_patterns

      Enum.any?(all_patterns, fn pattern ->
        pattern_matches?(signal.type, pattern)
      end)
    end)
  end

  # Checks if a signal type matches a pattern using glob-style matching.
  #
  # Parameters:
  #   - signal_type: The signal type to check
  #   - pattern: The pattern to match against (can include * wildcards)
  #
  # Returns:
  #   true if the signal type matches the pattern, false otherwise
  @spec pattern_matches?(signal_type :: String.t(), pattern :: String.t()) :: boolean()
  defp pattern_matches?(signal_type, pattern) do
    pattern
    |> String.replace(".", "\\.")
    |> String.replace("*", "[^.]+")
    |> then(&"^#{&1}$")
    |> Regex.compile!()
    |> Regex.match?(signal_type)
  end
end
