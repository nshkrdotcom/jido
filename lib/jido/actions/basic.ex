defmodule Jido.Actions.Basic do
  @moduledoc """
  A collection of basic actions for common workflows.
  """

  alias Jido.Action

  defmodule Sleep do
    @moduledoc "A action that simulates sleeping for a specified duration."
    use Action,
      name: "sleep_workflow",
      description: "Sleeps for a specified duration",
      schema: [
        duration_ms: [type: :non_neg_integer, default: 1000]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{duration_ms: duration} = params, _ctx) do
      Process.sleep(duration)
      {:ok, params}
    end
  end

  defmodule Log do
    @moduledoc "A action that logs a message with a specified level."
    use Action,
      name: "log_workflow",
      description: "Logs a message with a specified level",
      schema: [
        level: [type: {:in, [:debug, :info, :warn, :error]}, default: :info],
        message: [type: :string, required: true]
      ]

    require Logger

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{level: level, message: message} = params, _ctx) do
      case level do
        :debug -> Logger.debug(message)
        :info -> Logger.info(message)
        :warning -> Logger.warning(message)
        :error -> Logger.error(message)
      end

      {:ok, params}
    end
  end

  defmodule Todo do
    @moduledoc "A action that logs a message with a specified level."
    use Action,
      name: "todo_workflow",
      description: "A placeholder for a todo item",
      schema: [
        todo: [type: :string, required: true]
      ]

    require Logger

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{todo: todo} = params, _ctx) do
      Logger.info("TODO Action: #{todo}")
      {:ok, params}
    end
  end

  defmodule RandomSleep do
    @moduledoc "A action that introduces a random delay within a specified range."
    use Action,
      name: "random_sleep_workflow",
      description: "Introduces a random sleep within a specified range",
      schema: [
        min_ms: [type: :non_neg_integer, required: true],
        max_ms: [type: :non_neg_integer, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{min_ms: min, max_ms: max} = params, _ctx) do
      delay = Enum.random(min..max)
      Process.sleep(delay)
      {:ok, Map.put(params, :actual_delay, delay)}
    end
  end

  defmodule Increment do
    @moduledoc "An action that increments a value."
    use Action,
      name: "increment_workflow",
      description: "Increments a value by 1",
      schema: [
        value: [type: :integer, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value} = params, _ctx) do
      {:ok, Map.put(params, :value, value + 1)}
    end
  end

  defmodule Decrement do
    @moduledoc "An action that increments a value."
    use Action,
      name: "decrement_workflow",
      description: "Decrements a value by 1",
      schema: [
        value: [type: :integer, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value} = params, _ctx) do
      {:ok, Map.put(params, :value, value - 1)}
    end
  end
end
