defmodule Jido.Bus.Signal do
  @moduledoc """
  Signal contains the data for a single signal before being persisted to
  storage.
  """

  @type uuid :: String.t()

  @type t :: %Jido.Bus.Signal{
          jido_causation_id: uuid() | nil,
          jido_correlation_id: uuid(),
          type: String.t(),
          data: struct(),
          metadata: map()
        }

  defstruct [
    :jido_causation_id,
    :jido_correlation_id,
    :type,
    :data,
    :metadata
  ]
end
