defmodule JidoTest.Signal.Bus.SubscriberTest do
  use JidoTest.Case, async: true
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Bus.BusState
  alias Jido.Signal.Router

  describe "subscribe/5" do
    setup do
      state = %BusState{
        id: "test_bus",
        name: :test_bus,
        router: Router.new!(),
        subscriptions: %{},
        subscription_checkpoints: %{}
      }

      {:ok, state: state}
    end

    test "creates a new subscription with default options", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}
      route_path = "test.event.*"
      subscriber_id = "sub1"

      assert {:ok, new_state} = Subscriber.subscribe(state, subscriber_id, route_path, dispatch)

      # Verify the route was added to the router with the correct path pattern
      {:ok, routes} = Router.list(new_state.router)
      assert length(routes) == 1
      route = hd(routes)
      assert route.path == route_path
      assert route.target == dispatch

      # Verify subscription is tracked in state
      assert Map.has_key?(new_state.subscriptions, subscriber_id)
      subscription = Map.get(new_state.subscriptions, subscriber_id)
      assert subscription.id == subscriber_id
      assert subscription.path == route_path
      assert subscription.dispatch == dispatch
      refute subscription.persistent

      # Verify begin_timestamp is initialized
      assert Map.get(new_state.subscription_checkpoints, subscriber_id) == 0
    end

    test "creates a persistent subscription", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}
      route_path = "test.event.*"
      subscriber_id = "sub1"

      assert {:ok, new_state} =
               Subscriber.subscribe(state, subscriber_id, route_path, dispatch, persistent: true)

      # Verify the route was added to the router with the correct path pattern
      {:ok, routes} = Router.list(new_state.router)
      assert length(routes) == 1
      route = hd(routes)
      assert route.path == route_path
      assert route.target == dispatch

      # Verify subscription is tracked in state
      assert Map.has_key?(new_state.subscriptions, subscriber_id)
      subscription = Map.get(new_state.subscriptions, subscriber_id)
      assert subscription.id == subscriber_id
      assert subscription.path == route_path
      assert subscription.dispatch == dispatch
      assert subscription.persistent

      # Verify begin_timestamp is initialized
      assert Map.get(new_state.subscription_checkpoints, subscriber_id) == 0
    end

    test "fails to create duplicate subscription", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}
      route_path = "test.event.*"
      subscriber_id = "sub1"

      assert {:ok, state} = Subscriber.subscribe(state, subscriber_id, route_path, dispatch)
      assert {:error, _} = Subscriber.subscribe(state, subscriber_id, route_path, dispatch)
    end

    test "creates subscription with custom begin_timestamp", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}

      assert {:ok, new_state} =
               Subscriber.subscribe(state, "sub1", "test.event.*", dispatch,
                 persistent: true,
                 begin_timestamp: 42
               )

      assert Map.get(new_state.subscription_checkpoints, "sub1") == 42
    end

    test "reuses subscription id after complete deletion", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}

      # Create and delete with persistence removal
      assert {:ok, state} =
               Subscriber.subscribe(state, "sub1", "test.event.*", dispatch, persistent: true)

      assert {:ok, state} = Subscriber.unsubscribe(state, "sub1", delete_persistence: true)

      # Should be able to reuse the ID with different settings
      assert {:ok, new_state} =
               Subscriber.subscribe(state, "sub1", "different.path.*", dispatch,
                 persistent: false
               )

      subscription = Map.get(new_state.subscriptions, "sub1")
      assert subscription.path == "different.path.*"
      refute subscription.persistent
      assert Map.get(new_state.subscription_checkpoints, "sub1") == 0

      # Verify the new path pattern is used for routing
      {:ok, routes} = Router.list(new_state.router)
      assert length(routes) == 1
      route = hd(routes)
      assert route.path == "different.path.*"
      assert route.target == dispatch
    end
  end

  describe "unsubscribe/2" do
    setup do
      state = %BusState{
        id: "test_bus",
        name: :test_bus,
        router: Router.new!(),
        subscriptions: %{},
        subscription_checkpoints: %{}
      }

      {:ok, state: state}
    end

    test "removes an existing subscription with persistence", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}

      {:ok, state} =
        Subscriber.subscribe(state, "sub1", "test.event.*", dispatch, persistent: true)

      assert {:ok, new_state} = Subscriber.unsubscribe(state, "sub1")

      # Verify the route was removed from the router
      {:ok, routes} = Router.list(new_state.router)
      assert Enum.empty?(routes)

      # Verify subscription is removed but begin_timestamp remains
      refute Map.has_key?(new_state.subscriptions, "sub1")
      assert Map.has_key?(new_state.subscription_checkpoints, "sub1")

      # Should be able to resubscribe with same ID
      {:ok, resubscribed_state} =
        Subscriber.subscribe(new_state, "sub1", "test.event.*", dispatch, persistent: true)

      assert Map.has_key?(resubscribed_state.subscriptions, "sub1")
      assert Map.has_key?(resubscribed_state.subscription_checkpoints, "sub1")

      # Verify the path pattern is restored for routing
      {:ok, routes} = Router.list(resubscribed_state.router)
      assert length(routes) == 1
      route = hd(routes)
      assert route.path == "test.event.*"
      assert route.target == dispatch
    end

    test "removes an existing subscription with delete_persistence", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}

      {:ok, state} =
        Subscriber.subscribe(state, "sub1", "test.event.*", dispatch, persistent: true)

      assert {:ok, new_state} = Subscriber.unsubscribe(state, "sub1", delete_persistence: true)

      # Verify the route was removed from the router
      {:ok, routes} = Router.list(new_state.router)
      assert Enum.empty?(routes)

      # Verify subscription and begin_timestamp are both removed
      refute Map.has_key?(new_state.subscriptions, "sub1")
      refute Map.has_key?(new_state.subscription_checkpoints, "sub1")
    end

    test "fails to remove non-existent subscription", %{state: state} do
      assert {:error, _} = Subscriber.unsubscribe(state, "non_existent")
    end

    test "preserves begin_timestamp value across resubscribe", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}

      # Create subscription with custom begin_timestamp
      {:ok, state} =
        Subscriber.subscribe(state, "sub1", "test.event.*", dispatch,
          persistent: true,
          begin_timestamp: 42
        )

      # Unsubscribe without deleting persistence
      assert {:ok, state} = Subscriber.unsubscribe(state, "sub1")

      # Resubscribe and verify begin_timestamp is preserved
      assert {:ok, new_state} =
               Subscriber.subscribe(state, "sub1", "test.event.*", dispatch, persistent: true)

      assert Map.get(new_state.subscription_checkpoints, "sub1") == 42
    end

    test "allows resubscribe with different configuration", %{state: state} do
      dispatch = {:pid, target: self(), delivery_mode: :async}
      new_dispatch = {:pid, target: self(), delivery_mode: :sync}

      # Create initial subscription
      {:ok, state} =
        Subscriber.subscribe(state, "sub1", "test.event.*", dispatch, persistent: true)

      # Unsubscribe without deleting persistence
      assert {:ok, state} = Subscriber.unsubscribe(state, "sub1")

      # Resubscribe with different path and dispatch
      assert {:ok, new_state} =
               Subscriber.subscribe(state, "sub1", "different.path", new_dispatch,
                 persistent: true
               )

      subscription = Map.get(new_state.subscriptions, "sub1")
      assert subscription.path == "different.path"
      assert subscription.dispatch == new_dispatch
      assert subscription.persistent

      # Verify the new path is used for routing
      {:ok, routes} = Router.list(new_state.router)
      assert length(routes) == 1
      route = hd(routes)
      assert route.path == "different.path"
      assert route.target == new_dispatch
    end
  end
end
