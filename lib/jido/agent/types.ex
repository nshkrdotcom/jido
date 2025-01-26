defmodule Jido.Agent.Types do
  @moduledoc """
  Shared type definitions for Agent-related modules to avoid circular dependencies.
  """

  @type dispatch_config :: term()
  @type agent_id :: String.t()
  @type agent_info :: %{id: agent_id()}
end
