defmodule Jido.Agent.Port.Communication do
  @moduledoc """
  Port specification for agent communication mechanisms.
  Defines the interface for broadcasting events and managing subscriptions.
  """

  @type event_type :: atom()
  @type payload :: term()
  @type topic :: String.t()
  @type port_config :: term()

  @callback init(port_config()) :: {:ok, port_config()} | {:error, term()}
  @callback broadcast_event(port_config(), topic(), {event_type(), payload()}) ::
              :ok | {:error, term()}
  @callback subscribe(port_config(), topic()) :: :ok | {:error, term()}
  @callback unsubscribe(port_config(), topic()) :: :ok | {:error, term()}
end
