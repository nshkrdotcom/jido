defmodule JidoTest.Agent.StoreTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Store.ETS
  alias Jido.Agent.Store.File, as: FileStore
  alias Jido.Storage.ETS, as: UnifiedETS

  describe "ETS Store" do
    setup do
      table = :"test_ets_#{:erlang.unique_integer([:positive])}"

      on_exit(fn ->
        :ok = UnifiedETS.cleanup(table: table)
      end)

      {:ok, table: table}
    end

    test "put and get", %{table: table} do
      opts = [table: table]

      assert :ok = ETS.put(:key1, %{data: "test"}, opts)
      assert {:ok, %{data: "test"}} = ETS.get(:key1, opts)
    end

    test "get returns :not_found for missing key", %{table: table} do
      opts = [table: table]

      assert :not_found = ETS.get(:missing, opts)
    end

    test "delete removes key", %{table: table} do
      opts = [table: table]

      :ok = ETS.put(:key2, %{data: "test"}, opts)
      assert {:ok, _} = ETS.get(:key2, opts)

      :ok = ETS.delete(:key2, opts)
      assert :not_found = ETS.get(:key2, opts)
    end

    test "delete is idempotent", %{table: table} do
      opts = [table: table]

      assert :ok = ETS.delete(:never_existed, opts)
    end

    test "put overwrites existing", %{table: table} do
      opts = [table: table]

      :ok = ETS.put(:key3, %{v: 1}, opts)
      :ok = ETS.put(:key3, %{v: 2}, opts)

      assert {:ok, %{v: 2}} = ETS.get(:key3, opts)
    end

    test "handles complex keys", %{table: table} do
      opts = [table: table]
      key = {MyModule, "user-123"}

      :ok = ETS.put(key, %{count: 42}, opts)
      assert {:ok, %{count: 42}} = ETS.get(key, opts)
    end

    test "uses dedicated table owner/heir policy", %{table: table} do
      opts = [table: table]

      :ok = ETS.put(:ownership_key, %{count: 1}, opts)

      owner_pid = Process.whereis(Jido.Storage.ETS.Owner)
      heir_pid = Process.whereis(Jido.Storage.ETS.Heir)
      checkpoints = :"#{table}_checkpoints"

      assert owner_pid == :ets.info(checkpoints, :owner)
      assert heir_pid == :ets.info(checkpoints, :heir)
    end
  end

  describe "File Store" do
    setup do
      path =
        Path.join(System.tmp_dir!(), "jido_store_test_#{:erlang.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(path) end)
      {:ok, path: path}
    end

    test "put and get", %{path: path} do
      opts = [path: path]

      assert :ok = FileStore.put(:file_key1, %{data: "file_test"}, opts)
      assert {:ok, %{data: "file_test"}} = FileStore.get(:file_key1, opts)
    end

    test "get returns :not_found for missing key", %{path: path} do
      opts = [path: path]

      assert :not_found = FileStore.get(:missing, opts)
    end

    test "delete removes key", %{path: path} do
      opts = [path: path]

      :ok = FileStore.put(:file_key2, %{data: "test"}, opts)
      assert {:ok, _} = FileStore.get(:file_key2, opts)

      :ok = FileStore.delete(:file_key2, opts)
      assert :not_found = FileStore.get(:file_key2, opts)
    end

    test "delete is idempotent", %{path: path} do
      opts = [path: path]

      assert :ok = FileStore.delete(:never_existed, opts)
    end

    test "data survives 'restart' (re-read)", %{path: path} do
      opts = [path: path]

      :ok = FileStore.put(:persist_key, %{survives: true}, opts)

      # Simulate restart - new process reads the same file
      assert {:ok, %{survives: true}} = FileStore.get(:persist_key, opts)
    end

    test "handles complex keys and values", %{path: path} do
      opts = [path: path]
      key = {MyModule, "session-456"}

      value = %{
        id: "session-456",
        state: %{
          counter: 42,
          nested: %{deep: [1, 2, 3]}
        }
      }

      :ok = FileStore.put(key, value, opts)
      assert {:ok, ^value} = FileStore.get(key, opts)
    end

    test "creates directory if it doesn't exist", %{path: path} do
      nested_path = Path.join(path, "nested/deep/dir")
      opts = [path: nested_path]

      refute File.exists?(nested_path)

      :ok = FileStore.put(:key, %{data: 1}, opts)

      assert File.exists?(nested_path)
      assert {:ok, %{data: 1}} = FileStore.get(:key, opts)
    end
  end
end
