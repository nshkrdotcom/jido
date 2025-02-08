defmodule Jido.Bus.BusPrefixTestCase do
  import JidoTest.SharedTestCase

  define_tests do
    alias Jido.Signal

    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance]
    end

    describe "signal store prefix" do
      setup do
        {:ok, signal_store_meta1} = start_signal_store(name: :prefix1, prefix: "prefix1")
        {:ok, signal_store_meta2} = start_signal_store(name: :prefix2, prefix: "prefix2")

        [signal_store_meta1: signal_store_meta1, signal_store_meta2: signal_store_meta2]
      end

      test "should append signals to named signal store", %{
        signal_store: signal_store,
        signal_store_meta1: signal_store_meta1,
        signal_store_meta2: signal_store_meta2
      } do
        signals = build_signals(1)

        assert :ok == signal_store.publish(signal_store_meta1, "stream", 0, signals)

        assert {:error, :stream_not_found} ==
                 signal_store.replay(signal_store_meta2, "stream")
      end
    end

    defp build_signals(
           count,
           correlation_id \\ Jido.Util.generate_id(),
           causation_id \\ Jido.Util.generate_id()
         ) do
      for account_number <- 1..count,
          do: build_signal(account_number, correlation_id, causation_id)
    end

    defp build_signal(account_number, correlation_id, causation_id) do
      %Signal{
        id: correlation_id,
        source: causation_id,
        type: "#{__MODULE__}.BankAccountOpened",
        data: %{
          signal: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
          jido_metadata: %{"metadata" => "value"}
        }
      }
    end
  end
end
