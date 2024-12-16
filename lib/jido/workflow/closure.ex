defmodule Jido.Workflow.Closure do
  @moduledoc """
  Provides functionality to create closures around Jido Workflows (Actions).

  This module allows for partial application of context and options to actions,
  creating reusable workflow closures that can be executed with different parameters.
  """

  alias Jido.Error
  alias Jido.Workflow

  @type action :: Workflow.action()
  @type params :: Workflow.params()
  @type context :: Workflow.context()
  @type run_opts :: Workflow.run_opts()
  @type closure :: (params() -> {:ok, map()} | {:error, Error.t()})

  @doc """
  Creates a closure around a action with pre-applied context and options.

  ## Parameters

  - `action`: The action module to create a closure for.
  - `context`: The context to be applied to the action (default: %{}).
  - `opts`: The options to be applied to the action execution (default: []).

  ## Returns

  A function that takes params and returns the result of running the action.

  ## Examples

      iex> closure = Jido.Workflow.Closure.closure(MyAction, %{user_id: 123}, [timeout: 10_000])
      iex> closure.(%{input: "test"})
      {:ok, %{result: "processed test"}}

  """
  @spec closure(action(), context(), run_opts()) :: closure()
  def closure(action, context \\ %{}, opts \\ []) when is_atom(action) and is_list(opts) do
    fn params ->
      Workflow.run(action, params, context, opts)
    end
  end

  @doc """
  Creates an async closure around a action with pre-applied context and options.

  ## Parameters

  - `action`: The action module to create an async closure for.
  - `context`: The context to be applied to the action (default: %{}).
  - `opts`: The options to be applied to the action execution (default: []).

  ## Returns

  A function that takes params and returns an async reference.

  ## Examples

      iex> async_closure = Jido.Workflow.Closure.async_closure(MyAction, %{user_id: 123}, [timeout: 10_000])
      iex> async_ref = async_closure.(%{input: "test"})
      iex> Jido.Workflow.await(async_ref)
      {:ok, %{result: "processed test"}}

  """
  @spec async_closure(action(), context(), run_opts()) :: (params() -> Workflow.async_ref())
  def async_closure(action, context \\ %{}, opts \\ []) when is_atom(action) and is_list(opts) do
    fn params ->
      Workflow.run_async(action, params, context, opts)
    end
  end
end
