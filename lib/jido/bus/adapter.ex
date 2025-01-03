defmodule Jido.Bus.Adapter do
  @moduledoc """
  An adapter for the Jido Bus - providing signal distribution with optional persistence
  and replay capabilities.
  """

  @type bus :: pid | Jido.Bus.t()
  @type signal :: Jido.Signal.t()
  @type context :: map()
  @type config :: Keyword.t()
  @type adapter_meta :: map()
  @type stream_id :: String.t()
  @type start_from :: :origin | :current | integer
  @type expected_version :: :any_version | :no_stream | :stream_exists | non_neg_integer
  @type subscription_name :: String.t()
  @type subscription :: any()
  @type subscriber :: pid()
  @type source_id :: String.t()
  @type error :: term()

  @callback child_spec(context, opts :: Keyword.t()) ::
              {:ok, [:supervisor.child_spec() | {module, term} | module], bus}
              | {:error, :not_implemented}

  @callback publish(
              bus,
              stream_id,
              expected_version,
              signals :: list(Signal.t()),
              opts :: Keyword.t()
            ) ::
              :ok
              | {:error, :wrong_version}
              | {:error, :not_implemented}
              | {:error, error}

  @callback replay(
              bus,
              stream_id,
              start_version :: non_neg_integer,
              batch_size :: non_neg_integer
            ) ::
              {:ok, Enumerable.t()}
              | {:error, :stream_not_found}
              | {:error, :not_implemented}
              | {:error, error}

  @callback subscribe(bus, stream_id | :all) ::
              :ok
              | {:error, :not_implemented}
              | {:error, error}

  @callback subscribe_persistent(
              bus,
              stream_id | :all,
              subscription_name,
              subscriber,
              start_from,
              opts :: Keyword.t()
            ) ::
              {:ok, subscription}
              | {:error, :subscription_exists}
              | {:error, :not_implemented}
              | {:error, error}

  @callback ack(bus, pid, RecordedSignal.t()) ::
              :ok
              | {:error, :not_implemented}

  @callback unsubscribe(bus, subscription) ::
              :ok
              | {:error, :not_implemented}
              | {:error, error}

  @callback read_snapshot(bus, source_id) ::
              {:ok, Snapshot.t()}
              | {:error, :snapshot_not_found}
              | {:error, :not_implemented}

  @callback record_snapshot(bus, Snapshot.t()) ::
              :ok
              | {:error, :not_implemented}
              | {:error, error}

  @callback delete_snapshot(bus, source_id) ::
              :ok
              | {:error, :not_implemented}
              | {:error, error}
end
