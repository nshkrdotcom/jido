defmodule JidoTest.Signal.Bus.BusStateTest do
  use JidoTest.Case, async: true
  alias Jido.Signal.Bus.BusState
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Router

  describe "new BusState" do
    test "creates state with required fields" do
      state = %BusState{id: "test_bus", name: :test_bus}
      assert state.id == "test_bus"
      assert state.name == :test_bus
      assert state.config == []
      assert %Router.Router{} = state.router
      assert state.log == []
      refute state.route_signals
      assert state.snapshots == %{}
      assert state.subscriptions == %{}
      assert state.subscription_checkpoints == %{}
    end
  end

  describe "add_route/2" do
    setup do
      state = %BusState{id: "test_bus", name: :test_bus}
      route = %Router.Route{path: "test.*", target: {:pid, target: self()}, priority: 0}
      {:ok, state: state, route: route}
    end

    test "adds valid route to router", %{state: state, route: route} do
      assert {:ok, new_state} = BusState.add_route(state, route)
      {:ok, routes} = Router.list(new_state.router)
      assert length(routes) == 1
      assert hd(routes).path == route.path
    end

    test "returns error for invalid route", %{state: state} do
      invalid_route = %Router.Route{path: "invalid**path", target: {:pid, target: self()}}
      assert {:error, _reason} = BusState.add_route(state, invalid_route)
    end
  end

  describe "subscription management" do
    setup do
      state = %BusState{id: "test_bus", name: :test_bus}

      subscription = %Subscriber{
        id: "sub1",
        path: "test.*",
        dispatch: {:pid, target: self(), delivery_mode: :async},
        persistent: true
      }

      {:ok, state: state, subscription: subscription}
    end

    test "add_subscription adds new subscription", %{state: state, subscription: subscription} do
      assert {:ok, new_state} = BusState.add_subscription(state, "sub1", subscription)
      assert Map.has_key?(new_state.subscriptions, "sub1")
      assert Map.get(new_state.subscription_checkpoints, "sub1") == 0

      # Verify route was added
      {:ok, routes} = Router.list(new_state.router)
      assert length(routes) == 1
      assert hd(routes).path == subscription.path
    end

    test "add_subscription with custom begin_timestamp", %{
      state: state,
      subscription: subscription
    } do
      assert {:ok, new_state} =
               BusState.add_subscription(state, "sub1", subscription, begin_timestamp: 42)

      assert Map.get(new_state.subscription_checkpoints, "sub1") == 42
    end

    test "add_subscription fails for duplicate subscription", %{
      state: state,
      subscription: subscription
    } do
      {:ok, state} = BusState.add_subscription(state, "sub1", subscription)

      assert {:error, :subscription_exists} =
               BusState.add_subscription(state, "sub1", subscription)
    end

    test "remove_subscription removes subscription", %{state: state, subscription: subscription} do
      {:ok, state} = BusState.add_subscription(state, "sub1", subscription)
      assert {:ok, new_state} = BusState.remove_subscription(state, "sub1")
      refute Map.has_key?(new_state.subscriptions, "sub1")
      # Checkpoint remains by default
      assert Map.has_key?(new_state.subscription_checkpoints, "sub1")

      # Verify route was removed
      {:ok, routes} = Router.list(new_state.router)
      assert Enum.empty?(routes)
    end

    test "remove_subscription with delete_persistence", %{
      state: state,
      subscription: subscription
    } do
      {:ok, state} = BusState.add_subscription(state, "sub1", subscription)

      assert {:ok, new_state} =
               BusState.remove_subscription(state, "sub1", delete_persistence: true)

      refute Map.has_key?(new_state.subscriptions, "sub1")
      refute Map.has_key?(new_state.subscription_checkpoints, "sub1")
    end

    test "remove_subscription returns error for non-existent subscription", %{state: state} do
      assert {:error, :subscription_not_found} =
               BusState.remove_subscription(state, "non_existent")
    end

    test "has_subscription? checks subscription existence", %{
      state: state,
      subscription: subscription
    } do
      refute BusState.has_subscription?(state, "sub1")
      {:ok, state} = BusState.add_subscription(state, "sub1", subscription)
      assert BusState.has_subscription?(state, "sub1")
    end

    test "get_subscription retrieves subscription", %{state: state, subscription: subscription} do
      assert nil == BusState.get_subscription(state, "sub1")
      {:ok, state} = BusState.add_subscription(state, "sub1", subscription)
      assert ^subscription = BusState.get_subscription(state, "sub1")
    end
  end
end
