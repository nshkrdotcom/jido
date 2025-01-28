defmodule Jido.Chat.Channels.IExChannel.Server do
  use GenServer
  require Logger

  defmodule State do
    defstruct [:room_id, :bus_name]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def send_message(room_id, sender_id, content) do
    IO.puts("[#{room_id}] #{sender_id}: #{content}")
    :ok
  end

  def handle_incoming(room_id, message) do
    case message do
      %{sender_id: sender_id, content: content} ->
        IO.puts("[#{room_id}] #{sender_id}: #{content}")
        :ok

      _ ->
        {:error, :invalid_message}
    end
  end

  @impl true
  def init(opts) do
    {:ok, %State{room_id: opts[:room_id], bus_name: opts[:bus_name]}}
  end
end
