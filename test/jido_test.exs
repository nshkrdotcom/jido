defmodule JidoTest do
  use ExUnit.Case, async: true

  defmodule TestJido do
    use Jido, otp_app: :jido_test_app
  end

  @moduletag :capture_log

  describe "use Jido macro" do
    test "child_spec can be started under a supervisor" do
      # Set some config for :jido_test_app, TestJido
      Application.put_env(:jido_test_app, TestJido, name: TestJido)

      # Start the supervised instance
      {:ok, sup} = start_supervised(TestJido)

      # Verify it started a supervisor with the correct name
      assert Process.alive?(sup)
      # Could also check that the registry is started:
      registry_name = Module.concat(TestJido, "Registry")
      assert Process.whereis(registry_name)

      # or check dynamic supervisor
      dsup_name = Module.concat(TestJido, "AgentSupervisor")
      assert Process.whereis(dsup_name)
    end

    test "config is loaded from application env" do
      Application.put_env(:jido_test_app, TestJido, pubsub: "FakePubSub")
      assert TestJido.config()[:pubsub] == "FakePubSub"
    end
  end
end
