defmodule Jido.Runner do
  @moduledoc """
  Behavior for executing planned actions on an Agent.
  """

  @type action :: module() | {module(), map()}

  @callback run(agent :: struct(), opts :: keyword()) ::
              {:ok, struct()} | {:error, Jido.Error.t()}

  @doc """
  Normalizes actions into a list of instruction tuples {module, map()}.

  Accepts:
  • A single action module
  • A single action tuple {module, map()}
  • A list of modules
  • A list of action tuples {module, map()}

  ## Examples

      iex> normalize_instructions(MyAction)
      [{MyAction, %{}}]

      iex> normalize_instructions({MyAction, %{foo: :bar}})
      [{MyAction, %{foo: :bar}}]

      iex> normalize_instructions([MyAction1, MyAction2])
      [{MyAction1, %{}}, {MyAction2, %{}}]

      iex> normalize_instructions([{MyAction1, %{a: 1}}, {MyAction2, %{b: 2}}])
      [{MyAction1, %{a: 1}}, {MyAction2, %{b: 2}}]
  """
  @spec normalize_instructions(action() | [action()]) :: [{module(), map()}]
  def normalize_instructions(input) when is_atom(input) do
    [{input, %{}}]
  end

  def normalize_instructions({mod, args} = tuple) when is_atom(mod) and is_map(args) do
    [tuple]
  end

  def normalize_instructions(actions) when is_list(actions) do
    Enum.map(actions, fn
      mod when is_atom(mod) ->
        {mod, %{}}

      {mod, args} = tuple when is_atom(mod) and is_map(args) ->
        tuple
    end)
  end
end
