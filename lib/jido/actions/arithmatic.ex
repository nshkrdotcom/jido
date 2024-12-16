defmodule Jido.Actions.Arithmetic do
  @moduledoc """
  Provides basic arithmetic workflows as actions.
  """

  alias Jido.Action

  defmodule Add do
    @moduledoc "Adds two numbers"
    use Action,
      name: "add",
      description: "Adds two numbers",
      schema: [
        value: [type: :number, required: true],
        amount: [type: :number, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value + amount}}
    end
  end

  defmodule Subtract do
    @moduledoc "Subtracts one number from another"
    use Action,
      name: "subtract",
      description: "Subtracts one number from another",
      schema: [
        value: [type: :number, required: true],
        amount: [type: :number, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value - amount}}
    end
  end

  defmodule Multiply do
    @moduledoc "Multiplies two numbers"
    use Action,
      name: "multiply",
      description: "Multiplies two numbers",
      schema: [
        value: [type: :number, required: true],
        amount: [type: :number, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value * amount}}
    end
  end

  defmodule Divide do
    @moduledoc "Divides one number by another"
    use Action,
      name: "divide",
      description: "Divides one number by another",
      schema: [
        value: [type: :number, required: true],
        amount: [type: :number, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
    def run(%{value: _value, amount: 0}, _context) do
      {:error, "Cannot divide by zero"}
    end

    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value / amount}}
    end
  end

  defmodule Square do
    @moduledoc "Squares a number"
    use Action,
      name: "square",
      description: "Squares a number",
      schema: [
        value: [type: :number, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value}, _context) do
      {:ok, %{result: value * value}}
    end
  end
end
