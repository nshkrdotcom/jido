defmodule JidoTest.Agent.PersistenceTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Persistence
  alias Jido.Storage.ETS, as: UnifiedETS
  alias JidoTest.TestAgents.Minimal

  defp unique_table(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end

  test "hibernate/thaw works with legacy :store config" do
    table = unique_table("legacy_store")
    on_exit(fn -> :ok = UnifiedETS.cleanup(table: table) end)

    agent = Minimal.new(id: "legacy-agent", state: %{counter: 7})

    config = [store: {Jido.Agent.Store.ETS, table: table}]

    assert :ok = Persistence.hibernate(config, Minimal, "legacy-key", agent)
    assert {:ok, thawed} = Persistence.thaw(config, Minimal, "legacy-key")
    assert thawed.id == "legacy-agent"
    assert thawed.state.counter == 7
  end

  test "hibernate/thaw works with unified :storage config" do
    table = unique_table("unified_store")
    on_exit(fn -> :ok = UnifiedETS.cleanup(table: table) end)

    agent = Minimal.new(id: "unified-agent", state: %{counter: 11})

    config = [storage: {Jido.Storage.ETS, table: table}]

    assert :ok = Persistence.hibernate(config, Minimal, "unified-key", agent)
    assert {:ok, thawed} = Persistence.thaw(config, Minimal, "unified-key")
    assert thawed.id == "unified-agent"
    assert thawed.state.counter == 11
  end
end
