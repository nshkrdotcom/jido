defmodule Jido.Chat.Supervisor do
  @moduledoc """
  Supervisor for managing multiple chat rooms for a given bus.
  """
  use DynamicSupervisor
  alias Jido.Chat.Room

  @default_room_module Room

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_room(bus_name, room_id) do
    case do_start_room(bus_name, room_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def get_room(bus_name, room_id) do
    case Registry.lookup(Jido.Chat.Registry, {bus_name, room_id}) do
      [{pid, _}] ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def stop_room(bus_name, room_id) do
    case get_room(bus_name, room_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      error ->
        error
    end
  end

  defp do_start_room(bus_name, room_id) do
    name = Room.via_tuple(bus_name, room_id)
    room_module = Application.get_env(:jido, :chat_room_module, @default_room_module)

    DynamicSupervisor.start_child(
      __MODULE__,
      {room_module, [bus_name: bus_name, room_id: room_id, name: name]}
    )
  end

  def list_rooms(bus_name) do
    Registry.select(Jido.Chat.Registry, [
      {{{:"$1", :"$2"}, :_, :_}, [{:==, :"$1", bus_name}], [:"$2"]}
    ])
  end
end
