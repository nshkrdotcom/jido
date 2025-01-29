defmodule Jido.Runner do
  @moduledoc """
  Behavior for executing planned actions on an Agent.
  """

  @type action :: module() | {module(), map()}

  @callback run(agent :: struct(), opts :: keyword()) ::
              {:ok, struct(), list()} | {:error, Jido.Error.t()}
end
