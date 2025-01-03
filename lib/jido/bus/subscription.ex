defmodule Jido.Bus.Subscription do
  @moduledoc false

  use TypedStruct
  alias Jido.Bus
  alias Jido.Bus.RecordedSignal

  typedstruct do
    field(:bus, Bus.t(), enforce: true)
    field(:backoff, any(), enforce: true)
    field(:concurrency, pos_integer(), enforce: true)
    field(:partition_by, (RecordedSignal -> any()) | nil, default: nil)
    field(:subscribe_to, String.t() | :all, enforce: true)
    field(:subscribe_from, non_neg_integer() | :origin | :current, enforce: true)
    field(:subscription_name, String.t(), enforce: true)
    field(:subscription_opts, Keyword.t(), enforce: true)
    field(:subscription_pid, pid() | nil, default: nil)
    field(:subscription_ref, reference() | nil, default: nil)
  end

  def new(opts) do
    %__MODULE__{
      bus: Keyword.fetch!(opts, :bus),
      backoff: init_backoff(),
      concurrency: parse_concurrency(opts),
      partition_by: parse_partition_by(opts),
      subscription_name: Keyword.fetch!(opts, :subscription_name),
      subscription_opts: Keyword.fetch!(opts, :subscription_opts),
      subscribe_to: parse_subscribe_to(opts),
      subscribe_from: parse_subscribe_from(opts)
    }
  end

  @spec subscribe(__MODULE__.t(), pid()) :: {:ok, __MODULE__.t()} | {:error, any()}
  def subscribe(%__MODULE__{} = subscription, pid) do
    with {:ok, subscription_pid} <- subscribe_to(subscription, pid) do
      subscription_ref = Process.monitor(subscription_pid)

      subscription = %__MODULE__{
        subscription
        | subscription_pid: subscription_pid,
          subscription_ref: subscription_ref
      }

      {:ok, subscription}
    end
  end

  @spec backoff(__MODULE__.t()) :: {non_neg_integer(), __MODULE__.t()}
  def backoff(%__MODULE__{} = subscription) do
    %__MODULE__{backoff: backoff} = subscription

    {next, backoff} = :backoff.fail(backoff)

    subscription = %__MODULE__{subscription | backoff: backoff}

    {next, subscription}
  end

  @spec ack_signal(__MODULE__.t(), RecordedSignal.t()) :: :ok
  def ack_signal(%__MODULE__{} = subscription, %RecordedSignal{} = signal) do
    %__MODULE__{bus: bus, subscription_pid: subscription_pid} = subscription

    Bus.ack(bus, subscription_pid, signal)
  end

  @spec reset(__MODULE__.t()) :: __MODULE__.t()
  def reset(%__MODULE__{} = subscription) do
    %__MODULE__{
      bus: bus,
      subscription_pid: subscription_pid,
      subscription_ref: subscription_ref
    } = subscription

    Process.demonitor(subscription_ref)

    :ok = Bus.unsubscribe(bus, subscription_pid)

    %__MODULE__{
      subscription
      | backoff: init_backoff(),
        subscription_pid: nil,
        subscription_ref: nil
    }
  end

  defp subscribe_to(%__MODULE__{} = subscription, pid) do
    %__MODULE__{
      bus: bus,
      concurrency: concurrency,
      partition_by: partition_by,
      subscribe_to: subscribe_to,
      subscription_name: subscription_name,
      subscription_opts: subscription_opts,
      subscribe_from: subscribe_from
    } = subscription

    opts =
      subscription_opts
      |> Keyword.put(:concurrency_limit, concurrency)
      |> Keyword.put(:partition_by, partition_by)

    Bus.subscribe_persistent(
      bus,
      subscribe_to,
      subscription_name,
      pid,
      subscribe_from,
      opts
    )
  end

  defp parse_concurrency(opts) do
    case opts[:concurrency] || 1 do
      concurrency when is_integer(concurrency) and concurrency >= 1 ->
        concurrency

      invalid ->
        raise ArgumentError, message: "invalid `concurrency` option: " <> inspect(invalid)
    end
  end

  defp parse_partition_by(opts) do
    case opts[:partition_by] do
      partition_by when is_function(partition_by, 1) ->
        partition_by

      nil ->
        nil

      invalid ->
        raise ArgumentError, message: "invalid `partition_by` option: " <> inspect(invalid)
    end
  end

  defp parse_subscribe_to(opts) do
    case opts[:subscribe_to] || :all do
      :all ->
        :all

      stream when is_binary(stream) ->
        stream

      invalid ->
        raise ArgumentError, message: "invalid `subscribe_to` option: " <> inspect(invalid)
    end
  end

  defp parse_subscribe_from(opts) do
    case opts[:subscribe_from] || :origin do
      start_from when start_from in [:origin, :current] ->
        start_from

      start_from when is_integer(start_from) ->
        start_from

      invalid ->
        raise ArgumentError, message: "invalid `start_from` option: " <> inspect(invalid)
    end
  end

  @backoff_min :timer.seconds(1)
  @backoff_max :timer.minutes(1)

  # Exponential backoff with jitter
  defp init_backoff do
    :backoff.init(@backoff_min, @backoff_max) |> :backoff.type(:jitter)
  end
end
