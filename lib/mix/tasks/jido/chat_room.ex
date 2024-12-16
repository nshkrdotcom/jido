defmodule Mix.Tasks.Jido.ChatRoom do
  use Mix.Task

  @shortdoc "Starts a Jido chat room"

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          name: :string,
          strategy: :string
        ],
        aliases: [n: :name, s: :strategy]
      )

    Application.ensure_all_started(:jido)

    room_id = UUID.uuid4()
    strategy = parse_strategy(opts[:strategy])

    {:ok, _pid} = Jido.Room.start_link(room_id, name: {:via, Registry, {Jido.Registry, room_id}})

    IO.puts("""
    Chat room started!
    Room ID: #{room_id}
    Strategy: #{strategy}

    Use Jido.Room.post_message/3 to send messages
    """)

    Process.sleep(:infinity)
  end

  defp parse_strategy(nil), do: Jido.Room.Strategy.FreeForm
  defp parse_strategy("round_robin"), do: Jido.Room.Strategy.RoundRobin
  defp parse_strategy(_), do: Jido.Room.Strategy.FreeForm
end
