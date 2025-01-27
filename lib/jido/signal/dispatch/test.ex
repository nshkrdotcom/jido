defmodule Jido.Signal.Dispatch.Test do
  @moduledoc """
  Test implementation of signal dispatch for testing purposes.
  """

  alias Jido.Signal

  @doc """
  Test implementation of dispatch that always returns :ok
  """
  @spec dispatch(Signal.t(), term()) :: :ok
  def dispatch(%Signal{}, _config), do: :ok

  @doc """
  Test implementation of deliver that always returns :ok
  """
  @spec deliver(Signal.t(), term()) :: :ok
  def deliver(%Signal{}, _target), do: :ok

  @doc """
  Test implementation of validate_opts that always returns :ok
  """
  @spec validate_opts(keyword()) :: :ok
  def validate_opts(_opts), do: :ok
end
