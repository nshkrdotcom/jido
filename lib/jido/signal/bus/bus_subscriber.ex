defmodule Jido.Signal.Bus.Subscriber do
  use Private
  use TypedStruct

  alias Jido.Signal.Bus.BusState
  alias Jido.Error

  typedstruct do
    @typedoc """
    Represents a subscription to the signal bus.
    - id: Unique identifier for this subscription
    - path: The path pattern to match signals against
    - dispatch: The dispatch configuration for matched signals
    - persistent: Whether this subscription should persist across restarts
    - created_at: When this subscription was created
    """
    field(:id, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:dispatch, term(), enforce: true)
    field(:persistent, boolean(), default: false)
    field(:created_at, DateTime.t(), default: DateTime.utc_now())
  end

  @doc """
  Creates a new subscription in the bus state.
  Returns updated bus state or error.

  ## Options
    * :persistent - Whether the subscription should persist across restarts (default: false)
    * :begin_timestamp - Initial timestamp value for the subscription (default: 0 or existing timestamp)
  """
  @spec subscribe(BusState.t(), String.t(), String.t(), term(), keyword()) ::
          {:ok, BusState.t()} | {:error, Error.t()}
  def subscribe(%BusState{} = state, subscription_id, path, dispatch, opts \\ []) do
    # If resubscribing, use existing begin_timestamp unless explicitly provided
    opts =
      if Map.has_key?(state.subscription_checkpoints, subscription_id) do
        existing_timestamp = Map.get(state.subscription_checkpoints, subscription_id)
        Keyword.put_new(opts, :begin_timestamp, existing_timestamp)
      else
        opts
      end

    subscription = %__MODULE__{
      id: subscription_id,
      path: path,
      dispatch: dispatch,
      persistent: Keyword.get(opts, :persistent, false)
    }

    case BusState.add_subscription(state, subscription_id, subscription, opts) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, :subscription_exists} ->
        {:error,
         Error.validation_error("Subscription already exists", %{subscription_id: subscription_id})}

      {:error, reason} ->
        {:error, Error.execution_error("Failed to add subscription", reason)}
    end
  end

  @doc """
  Removes a subscription from the bus state.
  If delete_persistence is true, removes all subscription data.
  Otherwise, keeps checkpoint data for potential resubscription.
  Returns updated bus state or error.

  ## Options
    * :delete_persistence - Whether to remove all subscription data including checkpoints (default: false)
  """
  @spec unsubscribe(BusState.t(), String.t(), keyword()) ::
          {:ok, BusState.t()} | {:error, Error.t()}
  def unsubscribe(%BusState{} = state, subscription_id, opts \\ []) do
    case BusState.remove_subscription(state, subscription_id, opts) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, :subscription_not_found} ->
        {:error,
         Error.validation_error("Subscription does not exist", %{subscription_id: subscription_id})}

      {:error, reason} ->
        {:error, Error.execution_error("Failed to remove subscription", reason)}
    end
  end
end
