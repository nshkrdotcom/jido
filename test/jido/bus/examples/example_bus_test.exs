defmodule Jido.Bus.Examples.ExampleBusTest do
  use JidoTest.Case, async: true

  alias Jido.Bus
  alias Jido.Signal
  alias Jido.Bus.Snapshot

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  setup do
    test_name = :"test_#{:erlang.unique_integer()}"
    start_supervised!({Bus, name: test_name, adapter: :in_memory})
    {:ok, pid} = Bus.whereis(test_name)
    {:ok, %{test_name: test_name, bus: pid}}
  end

  test "pubsub bus can publish and subscribe to signals" do
    test_name = :"test_#{:erlang.unique_integer()}"
    pubsub_name = :"#{test_name}_pubsub"

    # Start Phoenix.PubSub
    start_supervised!({Phoenix.PubSub, name: pubsub_name})

    # Start bus with pubsub adapter
    start_supervised!({Bus, name: test_name, adapter: :pubsub, pubsub_name: pubsub_name})
    {:ok, bus} = Bus.whereis(test_name)

    signal = %Signal{
      id: Jido.Util.generate_id(),
      source: Jido.Util.generate_id(),
      type: "#{__MODULE__}.BankAccountOpened",
      data: %BankAccountOpened{account_number: 1, initial_balance: 1_000},
      jido_metadata: %{"metadata" => "value"}
    }

    :ok = Bus.subscribe(bus, "test_stream")

    # Wait for subscription confirmation
    assert_eventually(
      fn ->
        receive do
          {:subscribed, _subscription} -> true
          _ -> false
        after
          0 -> false
        end
      end,
      timeout: 1000
    )

    # Store subscription for later use
    subscription =
      receive do
        {:subscribed, sub} -> sub
      after
        0 -> nil
      end

    :ok = Bus.publish(bus, "test_stream", :any_version, [signal])

    # Wait for published signals
    assert_eventually(
      fn ->
        receive do
          {:signals, ^subscription, received_signals} ->
            length(received_signals) == 1 and
              hd(received_signals).data == signal.data

          _ ->
            false
        after
          0 -> false
        end
      end,
      timeout: 1000
    )
  end

  test "in-memory bus supports signal replay", %{bus: bus} do
    signals = [
      %Signal{
        id: Jido.Util.generate_id(),
        source: Jido.Util.generate_id(),
        type: "#{__MODULE__}.BankAccountOpened",
        data: %BankAccountOpened{account_number: 1, initial_balance: 1_000},
        jido_metadata: %{"metadata" => "value"}
      },
      %Signal{
        id: Jido.Util.generate_id(),
        source: Jido.Util.generate_id(),
        type: "#{__MODULE__}.BankAccountOpened",
        data: %BankAccountOpened{account_number: 2, initial_balance: 2_000},
        jido_metadata: %{"metadata" => "value"}
      }
    ]

    :ok = Bus.publish(bus, "test_stream", :any_version, signals)

    stream = Bus.replay(bus, "test_stream")
    read_signals = Enum.to_list(stream)
    assert length(read_signals) == 2
    assert Enum.map(read_signals, & &1.data) == Enum.map(signals, & &1.data)
  end

  test "in-memory bus supports snapshots", %{bus: bus} do
    snapshot = %Snapshot{
      source_id: Jido.Util.generate_id(),
      source_version: 1,
      source_type: "#{__MODULE__}.BankAccountOpened",
      data: %BankAccountOpened{account_number: 1, initial_balance: 1_000},
      jido_metadata: nil,
      created_at: DateTime.utc_now()
    }

    :ok = Bus.record_snapshot(bus, snapshot)
    assert {:ok, read_snapshot} = Bus.read_snapshot(bus, snapshot.source_id)
    assert read_snapshot.data == snapshot.data
  end
end
