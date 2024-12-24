defmodule Jido.Agent.Runtime.Signal do
  # @moduledoc """
  # Defines specialized signals for Agent Runtime communication and control.

  # This module provides functions for creating standardized signals used by the Agent Runtime
  # for operations like process management, state transitions, and command execution.
  # """
  alias Jido.Signal

  @agent_prefix "jido.agent."
  @syscall_prefix "jido.syscall."
  @event_prefix "jido.event."

  # Agent signals
  @agent_cmd "#{@agent_prefix}cmd"
  @agent_cmd_failed "#{@agent_prefix}cmd_failed"
  # Syscall signals
  @get_topic "#{@syscall_prefix}topic"
  @process_start "#{@syscall_prefix}start"
  @process_list "#{@syscall_prefix}list"
  @process_terminate "#{@syscall_prefix}terminate"
  # @pause "#{@syscall_prefix}pause"
  # @resume "#{@syscall_prefix}resume"

  # Event signals
  @started "#{@event_prefix}started"
  @stopped "#{@event_prefix}stopped"
  @transition_succeeded "#{@event_prefix}transition_succeeded"
  @transition_failed "#{@event_prefix}transition_failed"
  @queue_overflow "#{@event_prefix}queue_overflow"
  @queue_cleared "#{@event_prefix}queue_cleared"
  @process_started "#{@event_prefix}process_started"
  @process_terminated "#{@event_prefix}process_terminated"
  @process_restart_succeeded "#{@event_prefix}process_restart_succeeded"
  @process_restart_failed "#{@event_prefix}process_restart_failed"
  @process_start_failed "#{@event_prefix}process_start_failed"

  @signal_execution_started "#{@event_prefix}signal_execution_started"
  @signal_execution_completed "#{@event_prefix}signal_execution_completed"
  @signal_execution_failed "#{@event_prefix}signal_execution_failed"

  @queue_processing_started "#{@event_prefix}queue_processing_started"
  @queue_step_completed "#{@event_prefix}queue_step_completed"
  @queue_step_ignored "#{@event_prefix}queue_step_ignored"
  @queue_step_failed "#{@event_prefix}queue_step_failed"
  @queue_processing_completed "#{@event_prefix}queue_processing_completed"
  @queue_processing_failed "#{@event_prefix}queue_processing_failed"

  def agent_prefix, do: @agent_prefix
  def syscall_prefix, do: @syscall_prefix
  def event_prefix, do: @event_prefix

  def agent_cmd, do: @agent_cmd
  def agent_cmd_failed, do: @agent_cmd_failed
  def get_topic, do: @get_topic
  def process_start, do: @process_start
  def process_list, do: @process_list
  def process_terminate, do: @process_terminate
  def queue_step_completed, do: @queue_step_completed
  def queue_step_ignored, do: @queue_step_ignored
  def queue_step_failed, do: @queue_step_failed

  def started, do: @started
  def stopped, do: @stopped
  def transition_succeeded, do: @transition_succeeded
  def transition_failed, do: @transition_failed
  def queue_overflow, do: @queue_overflow
  def queue_cleared, do: @queue_cleared
  def process_started, do: @process_started
  def process_terminated, do: @process_terminated
  def process_restart_succeeded, do: @process_restart_succeeded
  def process_restart_failed, do: @process_restart_failed
  def process_start_failed, do: @process_start_failed
  def signal_execution_started, do: @signal_execution_started
  def signal_execution_completed, do: @signal_execution_completed
  def signal_execution_failed, do: @signal_execution_failed
  def queue_processing_started, do: @queue_processing_started
  def queue_processing_completed, do: @queue_processing_completed
  def queue_processing_failed, do: @queue_processing_failed
  def is_agent_signal?(%Signal{type: @agent_prefix <> _}), do: true
  def is_agent_signal?(_), do: false

  def is_syscall_signal?(%Signal{type: @syscall_prefix <> _}), do: true
  def is_syscall_signal?(_), do: false

  def is_process_start?(%Signal{type: @process_start}), do: true
  def is_process_start?(_), do: false

  def is_process_terminate?(%Signal{type: @process_terminate}), do: true
  def is_process_terminate?(_), do: false

  def syscall_to_signal(id, event_type, payload \\ %{}) do
    %Signal{
      id: Jido.Util.generate_id(),
      type: event_type,
      source: "/agent/#{id}",
      data: payload
    }
  end

  def event_to_signal(state, event_type, payload) do
    %Signal{
      id: Jido.Util.generate_id(),
      type: event_type,
      source: "/agent/#{state.agent.id}",
      data: payload
    }
  end

  @doc """
  Converts an action or list of actions into a signal.
  """
  def action_to_signal(agent_id, action, args \\ %{}, opts \\ [])

  def action_to_signal(agent_id, action, args, opts) when is_atom(action) do
    action_to_signal(agent_id, [{action, %{}}], args, opts)
  end

  def action_to_signal(agent_id, {action, action_args}, args, opts)
      when is_atom(action) and is_map(action_args) do
    action_to_signal(agent_id, [{action, action_args}], args, opts)
  end

  def action_to_signal(agent_id, actions, args, opts) when is_list(actions) do
    normalized_actions = normalize_actions(actions)

    extensions = %{
      "actions" => normalized_actions,
      "apply_state" => Keyword.get(opts, :apply_state, true)
    }

    %Signal{
      id: Jido.Util.generate_id(),
      type: @agent_cmd,
      source: "/agent/#{agent_id}",
      data: args,
      extensions: extensions
    }
  end

  @doc """
  Converts a signal back into an action tuple {action, params, opts}.
  """
  def signal_to_action(%Signal{} = signal) do
    with actions when is_list(actions) <- get_in(signal.extensions, ["actions"]),
         apply_state when is_boolean(apply_state) <- get_in(signal.extensions, ["apply_state"]) do
      {
        actions,
        signal.data,
        [apply_state: apply_state]
      }
    else
      _ -> {:error, :invalid_signal_format}
    end
  end

  # Private helper functions
  defp normalize_actions(actions) do
    Enum.map(actions, fn
      action when is_atom(action) -> {action, %{}}
      {action, args} = tuple when is_atom(action) and is_map(args) -> tuple
    end)
  end
end
