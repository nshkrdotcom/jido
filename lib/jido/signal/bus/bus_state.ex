defmodule Jido.Signal.Bus.BusState do
  use TypedStruct
  use ExDbug, enabled: false

  alias Jido.Signal.Router

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:name, atom(), enforce: true)
    field(:config, Keyword.t(), default: [])
    field(:router, Router.Router.t(), default: Router.new!())
    field(:log, list(Jido.Signal.t()), default: [])
    field(:route_signals, boolean(), default: false)
    field(:snapshots, %{String.t() => Jido.Signal.t()}, default: %{})
    field(:subscriptions, %{String.t() => Jido.Signal.Bus.Subscriber.t()}, default: %{})
    field(:subscription_checkpoints, %{String.t() => non_neg_integer()}, default: %{})
  end

  def add_route(state, route) do
    case Router.add(state.router, route) do
      {:ok, new_router} -> {:ok, %{state | router: new_router}}
      {:error, reason} -> {:error, reason}
    end
  end

  def remove_route(state, subscription_id) do
    case get_subscription(state, subscription_id) do
      nil ->
        {:ok, state}

      subscription ->
        # Get all current routes except the one we're removing
        {:ok, current_routes} = Router.list(state.router)

        # Create a route struct for comparison
        route_to_remove = subscription_to_route(subscription)

        remaining_routes =
          Enum.reject(current_routes, fn route ->
            route.path == route_to_remove.path &&
              compare_targets(route.target, route_to_remove.target)
          end)

        # Create a new router with the remaining routes
        case Router.new(remaining_routes) do
          {:ok, new_router} -> {:ok, %{state | router: new_router}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp compare_targets({:pid, opts1}, {:pid, opts2}) do
    # For PID targets, compare only the delivery mode
    Keyword.get(opts1, :delivery_mode) == Keyword.get(opts2, :delivery_mode)
  end

  defp compare_targets(target1, target2) do
    # For other targets, do a direct comparison
    target1 == target2
  end

  def has_subscription?(state, subscription_id) do
    Map.has_key?(state.subscriptions, subscription_id)
  end

  def get_subscription(state, subscription_id) do
    Map.get(state.subscriptions, subscription_id)
  end

  def add_subscription(state, subscription_id, subscription, opts \\ []) do
    if has_subscription?(state, subscription_id) do
      {:error, :subscription_exists}
    else
      # Use provided begin_timestamp or default to 0
      begin_timestamp = Keyword.get(opts, :begin_timestamp, 0)

      new_state = %{
        state
        | subscriptions: Map.put(state.subscriptions, subscription_id, subscription),
          subscription_checkpoints:
            Map.put(state.subscription_checkpoints, subscription_id, begin_timestamp)
      }

      add_route(new_state, subscription_to_route(subscription))
    end
  end

  def remove_subscription(state, subscription_id, opts \\ []) do
    if has_subscription?(state, subscription_id) do
      {subscription, new_subscriptions} = Map.pop(state.subscriptions, subscription_id)

      # If delete_persistence is true, remove all subscription data
      new_state =
        if Keyword.get(opts, :delete_persistence, false) do
          {_, new_checkpoints} = Map.pop(state.subscription_checkpoints, subscription_id)
          %{state | subscriptions: new_subscriptions, subscription_checkpoints: new_checkpoints}
        else
          # Keep the checkpoint for potential resubscription
          %{state | subscriptions: new_subscriptions}
        end

      case Router.remove(new_state.router, subscription.path) do
        {:ok, new_router} -> {:ok, %{new_state | router: new_router}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :subscription_not_found}
    end
  end

  defp subscription_to_route(subscription) do
    %Router.Route{
      # Use the path pattern for matching
      path: subscription.path,
      target: subscription.dispatch,
      priority: 0,
      # Let the Router's path matching handle wildcards
      match: nil
    }
  end
end
