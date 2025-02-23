# defmodule Jido.Signal.Bus.PersistentSubscription do
#   @moduledoc """
#   Manages persistent subscription state and checkpoints.
#   """
#   use TypedStruct
#   use ExDbug, enabled: true
#   alias Jido.Signal.Bus.Subscriber

#   typedstruct do
#     field(:name, String.t(), enforce: true)
#     field(:checkpoint, non_neg_integer(), default: 0)
#     field(:subscriber_pid, pid())
#     field(:start_from, :origin | :current | non_neg_integer(), default: :origin)
#     field(:max_in_flight, pos_integer(), default: 1000)
#     field(:client_pid, pid())
#   end

#   @doc """
#   Creates a new persistent subscription.
#   """
#   def new(name, opts \\ []) do
#     dbug("Creating new persistent subscription", name: name, opts: opts)

#     subscription = %__MODULE__{
#       name: name,
#       start_from: Keyword.get(opts, :start_from, :origin),
#       max_in_flight: Keyword.get(opts, :max_in_flight, 1000),
#       client_pid: Keyword.fetch!(opts, :client_pid)
#     }

#     dbug("Created subscription", subscription: subscription)
#     subscription
#   end

#   @doc """
#   Subscribes a process to the subscription.
#   """
#   def subscribe(%__MODULE__{} = subscription, bus_pid, subscriber_pid) do
#     dbug("Subscribing to persistent subscription",
#       subscription: subscription,
#       bus_pid: bus_pid,
#       subscriber_pid: subscriber_pid
#     )

#     # If a subscriber_pid is provided, use it directly
#     if subscriber_pid do
#       dbug("Resubscribing with existing subscriber", subscriber_pid: subscriber_pid)
#       # For resubscription, use the checkpoint
#       {:ok, %__MODULE__{subscription | subscriber_pid: subscriber_pid}}
#     else
#       # For initial subscription, use start_from
#       subscriber_args = [
#         bus_pid: bus_pid,
#         subscriber_id: subscription.name,
#         start_offset: get_start_offset(subscription),
#         max_in_flight: subscription.max_in_flight,
#         client_pid: subscription.client_pid
#       ]

#       dbug("Starting new subscriber", subscriber_args: subscriber_args)

#       case Subscriber.start_link(subscriber_args) do
#         {:ok, pid} ->
#           dbug("Subscriber started successfully", pid: pid)
#           {:ok, %__MODULE__{subscription | subscriber_pid: pid}}

#         error ->
#           dbug("Failed to start subscriber", error: error)
#           error
#       end
#     end
#   end

#   @doc """
#   Acknowledges a signal, updating the checkpoint.
#   """
#   def ack(%__MODULE__{} = subscription, signal_number) when is_integer(signal_number) do
#     dbug("Acknowledging signal",
#       subscription: subscription,
#       signal_number: signal_number,
#       current_checkpoint: subscription.checkpoint
#     )

#     if signal_number > subscription.checkpoint do
#       dbug("Updating checkpoint", new_checkpoint: signal_number)
#       {:ok, %__MODULE__{subscription | checkpoint: signal_number}}
#     else
#       dbug("Signal already acknowledged, keeping current checkpoint")
#       {:ok, subscription}
#     end
#   end

#   @doc """
#   Unsubscribes the current subscriber.
#   """
#   def unsubscribe(%__MODULE__{} = subscription) do
#     dbug("Unsubscribing from subscription", subscription: subscription)

#     if subscription.subscriber_pid do
#       dbug("Terminating subscriber process", subscriber_pid: subscription.subscriber_pid)
#       Process.exit(subscription.subscriber_pid, :normal)
#       {:ok, %__MODULE__{subscription | subscriber_pid: nil}}
#     else
#       dbug("No subscriber process to terminate")
#       {:ok, subscription}
#     end
#   end

#   # Private Helpers

#   defp get_start_offset(%__MODULE__{} = subscription) do
#     dbug("Calculating start offset", subscription: subscription)

#     offset =
#       case subscription.start_from do
#         :origin -> 0
#         # Add 1 for resubscription to skip acknowledged signal
#         :current -> subscription.checkpoint + 1
#         offset when is_integer(offset) -> max(offset, subscription.checkpoint + 1)
#       end

#     dbug("Calculated start offset", offset: offset)
#     offset
#   end
# end
