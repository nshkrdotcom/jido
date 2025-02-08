# Prepare modules for Mimic
Enum.each(
  [
    :telemetry,
    System
  ],
  &Mimic.copy/1
)

ExUnit.start()

defmodule Jido.Memory.TestHelpers do
  def cleanup_ets_tables do
    # Delete any existing test tables
    :ets.all()
    |> Enum.filter(fn table ->
      case table do
        table when is_atom(table) ->
          name = Atom.to_string(table)

          String.starts_with?(name, "test_") or String.starts_with?(name, "default_") or
            String.starts_with?(name, "custom_") or String.starts_with?(name, "jido_memory_")

        _ ->
          false
      end
    end)
    |> Enum.each(fn table ->
      try do
        :ets.delete(table)
      rescue
        ArgumentError -> :ok
      end
    end)
  end
end

ExUnit.configure(exclude: [:skip])
