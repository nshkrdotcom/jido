defmodule Jido.Actions.Syscall do
  @moduledoc """
  Actions for executing system calls from within agent workflows.
  These actions provide controlled access to runtime operations.
  """

  alias Jido.Action

  defmodule Spawn do
    @moduledoc false
    use Action,
      name: "spawn_process",
      description: "Spawns a child process under the agent's supervisor",
      schema: [
        module: [type: :atom, required: true, doc: "Module to spawn"],
        args: [type: :any, required: true, doc: "Arguments to pass to the module"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{module: module, args: args}, _ctx) do
      {:ok, {:syscall, {:spawn, module, args}}}
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

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{pid: pid}, _ctx) do
      {:ok, {:syscall, {:kill, pid}}}
    end
  end

  defmodule EnqueueCmd do
    @moduledoc false
    use Action,
      name: "enqueue_command",
      description: "Enqueues a command for later execution",
      schema: [
        cmd: [type: :atom, required: true, doc: "Command to enqueue"],
        params: [type: :map, required: true, doc: "Command parameters"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{cmd: cmd, params: params}, _ctx) do
      {:ok, {:syscall, {:enqueue, cmd, params}}}
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

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{topic: topic, message: msg}, _ctx) do
      {:ok, {:syscall, {:broadcast, topic, msg}}}
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

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{topic: topic}, _ctx) do
      {:ok, {:syscall, {:subscribe, topic}}}
    end
  end

  defmodule Checkpoint do
    @moduledoc false
    use Action,
      name: "create_checkpoint",
      description: "Creates a state checkpoint",
      schema: [
        key: [type: :any, required: true, doc: "Checkpoint identifier"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{key: key}, _ctx) do
      {:ok, {:syscall, {:checkpoint, key}}}
    end
  end
end
