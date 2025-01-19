defmodule Jido.Chat.Channels.IExChannel do
  @behaviour Jido.Chat.Channel
  alias Jido.Chat.Channels.IExChannel.Server

  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def send_message(room_id, sender_id, content, _opts) do
    Server.send_message(room_id, sender_id, content)
  end

  @impl true
  def handle_incoming(room_id, message) do
    Server.handle_incoming(room_id, message)
  end

  def init(opts) do
    {:ok, opts}
  end
end
