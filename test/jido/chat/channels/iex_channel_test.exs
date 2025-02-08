defmodule Jido.Chat.Channels.IExChannelTest do
  use JidoTest.Case, async: true
  alias Jido.Chat.Channels.IExChannel
  import ExUnit.CaptureIO

  describe "start_link/1" do
    test "starts the IEx channel server" do
      opts = [name: :test_iex_channel]
      assert {:ok, pid} = IExChannel.start_link(opts)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end

  describe "send_message/4" do
    test "prints the message to stdout" do
      output =
        capture_io(fn ->
          assert :ok = IExChannel.send_message("room1", "user1", "Hello!", [])
        end)

      assert output =~ "[room1] user1: Hello!"
    end
  end

  describe "handle_incoming/2" do
    test "prints valid incoming messages" do
      message = %{sender_id: "user1", content: "Hello!"}

      output =
        capture_io(fn ->
          assert :ok = IExChannel.handle_incoming("room1", message)
        end)

      assert output =~ "[room1] user1: Hello!"
    end

    test "returns error for invalid messages" do
      assert {:error, :invalid_message} =
               IExChannel.handle_incoming("room1", %{invalid: "message"})
    end
  end
end
