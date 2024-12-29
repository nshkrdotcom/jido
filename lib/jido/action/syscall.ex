defmodule Jido.Actions.Syscall do
  @moduledoc """
  Actions for executing system calls from within agent workflows.
  These actions provide controlled access to server operations.
  """

  alias Jido.Action

  alias Jido.Agent.Syscall.{
    SpawnSyscall,
    KillSyscall,
    BroadcastSyscall,
    SubscribeSyscall,
    UnsubscribeSyscall
  }

  defmodule Spawn do
    @moduledoc false
    use Action,
      name: "spawn_process",
      description: "Spawns a child process under the agent's supervisor",
      schema: [
        module: [type: :atom, required: true, doc: "Module to spawn"],
        args: [type: :any, required: true, doc: "Arguments to pass to the module"]
      ]

    @spec run(map(), map()) :: {:ok, SpawnSyscall.t()} | {:error, term()}
    def run(%{module: module, args: args}, _ctx) do
      syscall = %SpawnSyscall{
        module: module,
        args: args
      }

      {:ok, syscall}
    end
  end

  defmodule Kill do
    @moduledoc false
    use Action,
      name: "kill_process",
      description: "Terminates a child process",
      schema: [
        pid: [type: :pid, required: true, doc: "PID of process to terminate"]
      ]

    @spec run(map(), map()) :: {:ok, KillSyscall.t()} | {:error, term()}
    def run(%{pid: pid}, _ctx) do
      syscall = %KillSyscall{pid: pid}
      {:ok, syscall}
    end
  end

  defmodule Broadcast do
    @moduledoc false
    use Action,
      name: "broadcast_message",
      description: "Broadcasts a message on a PubSub topic",
      schema: [
        topic: [type: :string, required: true, doc: "Topic to broadcast on"],
        message: [type: :any, required: true, doc: "Message to broadcast"]
      ]

    @spec run(map(), map()) :: {:ok, BroadcastSyscall.t()} | {:error, term()}
    def run(%{topic: topic, message: msg}, _ctx) do
      syscall = %BroadcastSyscall{
        topic: topic,
        message: msg
      }

      {:ok, syscall}
    end
  end

  defmodule Subscribe do
    @moduledoc false
    use Action,
      name: "subscribe_topic",
      description: "Subscribes to a PubSub topic",
      schema: [
        topic: [type: :string, required: true, doc: "Topic to subscribe to"]
      ]

    @spec run(map(), map()) :: {:ok, SubscribeSyscall.t()} | {:error, term()}
    def run(%{topic: topic}, _ctx) do
      syscall = %SubscribeSyscall{topic: topic}
      {:ok, syscall}
    end
  end

  defmodule Unsubscribe do
    @moduledoc false
    use Action,
      name: "unsubscribe_topic",
      description: "Unsubscribes from a PubSub topic",
      schema: [
        topic: [type: :string, required: true, doc: "Topic to unsubscribe from"]
      ]

    @spec run(map(), map()) :: {:ok, UnsubscribeSyscall.t()} | {:error, term()}
    def run(%{topic: topic}, _ctx) do
      syscall = %UnsubscribeSyscall{topic: topic}
      {:ok, syscall}
    end
  end
end
