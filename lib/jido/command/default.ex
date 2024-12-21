defmodule Jido.Commands.Default do
  @moduledoc """
  Provides default commands available to all Agents.
  """
  use Jido.Command
  alias Jido.Actions.Basic.{Log, Sleep, Noop, Inspect}

  @impl true
  def commands do
    [
      default: [
        description: "Default command",
        schema: []
      ],
      log: [
        description: "Default log command",
        schema: [
          message: [type: :string, default: ""]
        ]
      ],
      sleep: [
        description: "Pauses execution for specified duration",
        schema: [
          duration: [type: :integer, default: 1000]
        ]
      ],
      noop: [
        description: "No operation, returns input unchanged",
        schema: []
      ],
      inspect: [
        description: "Inspects a value",
        schema: [
          value: [type: :any, required: true, doc: "Value to inspect"]
        ]
      ]
    ]
  end

  @impl true
  def handle_command(:default, _agent, _params) do
    {:ok, []}
  end

  @impl true
  def handle_command(:log, _agent, %{message: message}) do
    {:ok, [{Log, [message: message]}]}
  end

  def handle_command(:sleep, _agent, %{duration: duration}) do
    {:ok, [{Sleep, duration_ms: duration}]}
  end

  def handle_command(:sleep, _agent, _params) do
    {:ok, [Sleep]}
  end

  def handle_command(:noop, _agent, _params) do
    {:ok, [Noop]}
  end

  def handle_command(:inspect, _agent, %{value: value}) do
    {:ok, [{Inspect, value: value}]}
  end
end
