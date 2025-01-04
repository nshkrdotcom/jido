defmodule Commanded.Application do
  def signal_store_adapter(_application) do
    {Jido.Bus.Adapters.InMemory, name: :signal_store}
  end
end
