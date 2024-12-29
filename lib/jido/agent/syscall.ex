defmodule Jido.Agent.Syscall do
  @moduledoc """
  Provides a type-safe way to execute system commands that affect agent server behavior.

  ## Overview

  Syscalls are immutable instructions that can be executed by the agent server to perform
  system-level operations like spawning processes, broadcasting messages, etc. Each syscall
  type is implemented as a separate struct with its own validation rules.

  ## Available Syscalls

  * `SpawnSyscall` - Spawns a child process under the agent's supervisor
      - Requires a module atom and arguments
      - Example: `%SpawnSyscall{module: MyWorker, args: [id: 1]}`

  * `KillSyscall` - Terminates a child process
      - Requires a valid PID
      - Example: `%KillSyscall{pid: #PID<0.123.0>}`

  * `BroadcastSyscall` - Broadcasts a message on a PubSub topic
      - Requires a topic string and message
      - Example: `%BroadcastSyscall{topic: "events", message: %{type: :update}}`

  * `SubscribeSyscall` - Subscribes to a PubSub topic
      - Requires a topic string
      - Example: `%SubscribeSyscall{topic: "events"}`

  * `UnsubscribeSyscall` - Unsubscribes from a PubSub topic
      - Requires a topic string
      - Example: `%UnsubscribeSyscall{topic: "events"}`

  ## Validation

  Each syscall type has its own validation rules to ensure type safety and valid parameters.
  Failed validation results in an error tuple being returned.
  """

  use TypedStruct

  typedstruct module: SpawnSyscall do
    @typedoc "Syscall to spawn a child process"
    field(:module, module(), enforce: true)
    field(:args, term(), enforce: true)
  end

  typedstruct module: KillSyscall do
    @typedoc "Syscall to terminate a child process"
    field(:pid, pid(), enforce: true)
  end

  typedstruct module: BroadcastSyscall do
    @typedoc "Syscall to broadcast a message"
    field(:topic, String.t(), enforce: true)
    field(:message, term(), enforce: true)
  end

  typedstruct module: SubscribeSyscall do
    @typedoc "Syscall to subscribe to a topic"
    field(:topic, String.t(), enforce: true)
  end

  typedstruct module: UnsubscribeSyscall do
    @typedoc "Syscall to unsubscribe from a topic"
    field(:topic, String.t(), enforce: true)
  end

  @type t ::
          SpawnSyscall.t()
          | KillSyscall.t()
          | EnqueueCmdSyscall.t()
          | BroadcastSyscall.t()
          | SubscribeSyscall.t()
          | UnsubscribeSyscall.t()

  @doc """
  Checks if a value is a valid syscall struct.

  ## Parameters
    - value: Any value to check

  ## Returns
    - `true` if the value is a valid syscall struct
    - `false` otherwise

  ## Examples

      iex> is_syscall?(%SpawnSyscall{module: MyWorker, args: []})
      true

      iex> is_syscall?(:not_a_syscall)
      false
  """
  @spec is_syscall?(term()) :: boolean()
  def is_syscall?(syscall) when is_struct(syscall, SpawnSyscall), do: true
  def is_syscall?(syscall) when is_struct(syscall, KillSyscall), do: true
  def is_syscall?(syscall) when is_struct(syscall, BroadcastSyscall), do: true
  def is_syscall?(syscall) when is_struct(syscall, SubscribeSyscall), do: true
  def is_syscall?(syscall) when is_struct(syscall, UnsubscribeSyscall), do: true
  def is_syscall?(_), do: false

  @doc """
  Validates a syscall struct based on its type.

  ## Parameters
    - syscall: The syscall struct to validate

  ## Returns
    - `:ok` if validation passes
    - `{:error, reason}` if validation fails

  ## Examples

      iex> validate_syscall(%SpawnSyscall{module: MyWorker, args: []})
      :ok

      iex> validate_syscall(%SpawnSyscall{module: nil, args: []})
      {:error, :invalid_module}
  """
  @spec validate_syscall(t()) :: :ok | {:error, term()}
  def validate_syscall(%SpawnSyscall{module: nil}), do: {:error, :invalid_module}
  def validate_syscall(%SpawnSyscall{module: mod}) when is_atom(mod), do: :ok

  def validate_syscall(%KillSyscall{pid: pid}) when is_pid(pid), do: :ok
  def validate_syscall(%KillSyscall{}), do: {:error, :invalid_pid}

  def validate_syscall(%BroadcastSyscall{topic: topic}) when is_binary(topic), do: :ok
  def validate_syscall(%BroadcastSyscall{}), do: {:error, :invalid_topic}

  def validate_syscall(%SubscribeSyscall{topic: topic}) when is_binary(topic), do: :ok
  def validate_syscall(%SubscribeSyscall{}), do: {:error, :invalid_topic}

  def validate_syscall(%UnsubscribeSyscall{topic: topic}) when is_binary(topic), do: :ok
  def validate_syscall(%UnsubscribeSyscall{}), do: {:error, :invalid_topic}

  def validate_syscall(_), do: {:error, :invalid_syscall}
end
