defmodule Jido.Chat.Channel do
  @moduledoc """
  Defines the behavior for chat channels.

  A channel is responsible for handling the input/output of messages for a chat room.
  It can be used to integrate with different interfaces like IEx, HTTP, WebSocket, etc.
  """

  @doc """
  Starts a new channel process.
  """
  @callback start_link(opts :: Keyword.t()) :: GenServer.on_start()

  @doc """
  Sends a message to the channel.
  """
  @callback send_message(
              room_id :: String.t(),
              sender_id :: String.t(),
              content :: String.t(),
              opts :: Keyword.t()
            ) ::
              :ok | {:error, term()}

  @doc """
  Handles an incoming message from the channel.
  """
  @callback handle_incoming(room_id :: String.t(), message :: map()) ::
              :ok | {:error, term()}
end
