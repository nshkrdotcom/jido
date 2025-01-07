defmodule Jido.Signal.RouterTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Router

  @moduletag :capture_log

  describe "new/0 and new/1" do
    test "creates an empty router" do
      assert Router.new() == %{}
    end

    test "creates router with path routes" do
      handler = fn _ -> :ok end
      routes = [{"payment.created", handler}]

      router = Router.new(routes)

      assert %{
               "payment" => %{
                 "created" => %{handler: {^handler, 0}}
               }
             } = router
    end

    test "creates router with path routes and priority" do
      handler = fn _ -> :ok end
      routes = [{"payment.created", handler, 10}]

      router = Router.new(routes)

      assert %{
               "payment" => %{
                 "created" => %{handler: {^handler, 10}}
               }
             } = router
    end

    test "creates router with pattern routes" do
      pattern = fn %Signal{data: %{amount: amount}} -> amount > 1000 end
      handler = fn _ -> :ok end
      routes = [{"payment", pattern, handler}]

      router = Router.new(routes)

      assert %{
               "payment" => %{
                 matchers: [{^pattern, ^handler, 0}]
               }
             } = router
    end

    test "creates router with pattern routes and priority" do
      pattern = fn %Signal{data: %{amount: amount}} -> amount > 1000 end
      handler = fn _ -> :ok end
      routes = [{"payment", pattern, handler, 10}]

      router = Router.new(routes)

      assert %{
               "payment" => %{
                 matchers: [{^pattern, ^handler, 10}]
               }
             } = router
    end

    test "creates router with mixed routes" do
      path_handler = fn _ -> :path end
      pattern = fn %Signal{data: %{amount: amount}} -> amount > 1000 end
      pattern_handler = fn _ -> :pattern end

      routes = [
        {"payment.created", path_handler, 5},
        {"payment", pattern, pattern_handler, 10}
      ]

      router = Router.new(routes)

      assert %{
               "payment" => %{
                 "created" => %{handler: {^path_handler, 5}},
                 matchers: [{^pattern, ^pattern_handler, 10}]
               }
             } = router
    end

    test "returns empty router on invalid route specs" do
      routes = [
        {"invalid", "not a function"},
        {123, fn _ -> :ok end}
      ]

      assert Router.new(routes) == %{}
    end
  end

  describe "add_path_route/3 and add_path_route/4" do
    test "adds a simple path route" do
      router =
        Router.new()
        |> Router.add_path_route("payment.created", fn _ -> :ok end)

      assert %{"payment" => %{"created" => %{handler: {_handler, 0}}}} = router
    end

    test "adds path route with priority" do
      router =
        Router.new()
        |> Router.add_path_route("payment.created", fn _ -> :ok end, 10)

      assert %{"payment" => %{"created" => %{handler: {_handler, 10}}}} = router
    end

    test "adds multiple path routes" do
      router =
        Router.new()
        |> Router.add_path_route("payment.created", fn _ -> :created end, 10)
        |> Router.add_path_route("payment.updated", fn _ -> :updated end, 5)

      assert %{
               "payment" => %{
                 "created" => %{handler: {_, 10}},
                 "updated" => %{handler: {_, 5}}
               }
             } = router
    end

    test "adds wildcard route" do
      router =
        Router.new()
        |> Router.add_path_route("payment.*", fn _ -> :any end, 1)

      assert %{"payment" => %{"*" => %{handler: {_, 1}}}} = router
    end

    test "returns error on invalid path format" do
      assert {:error, :invalid_path_format} =
               Router.add_path_route(%{}, "invalid..path", fn _ -> :ok end)
    end

    test "returns error on invalid handler" do
      assert {:error, :invalid_handler} = Router.add_path_route(%{}, "payment", "not a function")
    end

    test "returns error on invalid priority" do
      assert {:error, :invalid_priority} =
               Router.add_path_route(%{}, "payment", fn _ -> :ok end, "high")
    end
  end

  describe "add_pattern_route/4 and add_pattern_route/5" do
    test "adds a pattern route" do
      router =
        Router.new()
        |> Router.add_pattern_route(
          "payment",
          fn %Signal{data: %{amount: amount}} -> amount > 1000 end,
          fn _ -> :large_payment end
        )

      assert %{"payment" => %{matchers: [{_pattern_fn, _handler, 0}]}} = router
    end

    test "adds pattern route with priority" do
      router =
        Router.new()
        |> Router.add_pattern_route(
          "payment",
          fn %Signal{data: %{amount: amount}} -> amount > 1000 end,
          fn _ -> :large_payment end,
          10
        )

      assert %{"payment" => %{matchers: [{_pattern_fn, _handler, 10}]}} = router
    end

    test "adds multiple pattern routes" do
      router =
        Router.new()
        |> Router.add_pattern_route(
          "payment",
          fn %Signal{data: %{amount: amount}} -> amount > 1000 end,
          fn _ -> :large_payment end,
          10
        )
        |> Router.add_pattern_route(
          "payment",
          fn %Signal{data: %{currency: currency}} -> currency == "USD" end,
          fn _ -> :usd_payment end,
          5
        )

      assert %{"payment" => %{matchers: matchers}} = router
      assert length(matchers) == 2
      assert Enum.any?(matchers, fn {_, _, priority} -> priority == 10 end)
      assert Enum.any?(matchers, fn {_, _, priority} -> priority == 5 end)
    end

    test "returns error on invalid pattern function" do
      assert {:error, :invalid_pattern_function} =
               Router.add_pattern_route(
                 %{},
                 "payment",
                 fn _ -> "not a boolean" end,
                 fn _ -> :ok end
               )
    end
  end

  describe "route/2" do
    test "routes to exact path handler" do
      router =
        Router.new()
        |> Router.add_path_route("payment.created", fn _ -> :created end, 1)

      signal = %Signal{type: "payment.created", source: "test", id: "test-1"}
      assert {:ok, [:created]} = Router.route(router, signal)
    end

    test "routes to wildcard handler" do
      router =
        Router.new()
        |> Router.add_path_route("payment.*", fn _ -> :any end, 1)

      signal = %Signal{type: "payment.created", source: "test", id: "test-1"}
      assert {:ok, [:any]} = Router.route(router, signal)
    end

    test "routes to pattern handler when condition matches" do
      router =
        Router.new()
        |> Router.add_pattern_route(
          "payment",
          fn %Signal{data: %{amount: amount}} -> amount > 1000 end,
          fn _ -> :large_payment end,
          10
        )

      signal = %Signal{type: "payment", data: %{amount: 2000}, source: "test", id: "test-1"}
      assert {:ok, [:large_payment]} = Router.route(router, signal)
    end

    test "executes multiple matching handlers in priority order" do
      router =
        Router.new()
        |> Router.add_pattern_route(
          "payment",
          fn %Signal{data: %{amount: amount}} -> amount > 1000 end,
          fn _ -> :large end,
          10
        )
        |> Router.add_pattern_route(
          "payment",
          fn %Signal{data: %{currency: currency}} -> currency == "USD" end,
          fn _ -> :usd end,
          5
        )
        |> Router.add_path_route("payment", fn _ -> :any end, 1)

      signal = %Signal{
        type: "payment",
        data: %{amount: 2000, currency: "USD"},
        source: "test",
        id: "test-1"
      }

      assert {:ok, [:large, :usd, :any]} = Router.route(router, signal)
    end

    test "returns error when no handler found" do
      router = Router.new()
      signal = %Signal{type: "unknown.event", source: "test", id: "test-1"}
      assert {:error, :no_handler} = Router.route(router, signal)
    end
  end

  # describe "remove_route/2" do
  #   test "removes path route" do
  #     router =
  #       Router.new()
  #       |> Router.add_path_route("payment", fn _ -> :any end)
  #       |> Router.remove_route("payment")

  #     signal = %Signal{type: "payment", source: "test", id: "test-1"}
  #     assert {:error, :no_handler} = Router.route(router, signal)
  #   end

  #   test "removes nested path route" do
  #     router =
  #       Router.new()
  #       |> Router.add_path_route("payment.success", fn _ -> :success end)
  #       |> Router.remove_route("payment.success")

  #     signal = %Signal{type: "payment.success", source: "test", id: "test-1"}
  #     assert {:error, :no_handler} = Router.route(router, signal)
  #   end
  # end

  # describe "remove_pattern_route/3" do
  #   test "removes pattern route" do
  #     pattern_fn = fn %Signal{data: %{amount: amount}} -> amount > 1000 end

  #     router =
  #       Router.new()
  #       |> Router.add_pattern_route("payment", pattern_fn, fn _ -> :large end)
  #       |> Router.remove_pattern_route("payment", pattern_fn)

  #     signal = %Signal{type: "payment", data: %{amount: 2000}, source: "test", id: "test-1"}
  #     assert {:error, :no_handler} = Router.route(router, signal)
  #   end

  #   test "removes only matching pattern route" do
  #     pattern_1 = fn %Signal{data: %{amount: amount}} -> amount > 1000 end
  #     pattern_2 = fn %Signal{data: %{currency: currency}} -> currency == "USD" end

  #     router =
  #       Router.new()
  #       |> Router.add_pattern_route("payment", pattern_1, fn _ -> :large end)
  #       |> Router.add_pattern_route("payment", pattern_2, fn _ -> :usd end)
  #       |> Router.remove_pattern_route("payment", pattern_1)

  #     signal = %Signal{
  #       type: "payment",
  #       data: %{amount: 2000, currency: "USD"},
  #       source: "test",
  #       id: "test-1"
  #     }

  #     assert {:ok, [:usd]} = Router.route(router, signal)
  #   end
  # end

  # describe "list_routes/1" do
  #   test "lists path routes" do
  #     router =
  #       Router.new()
  #       |> Router.add_path_route("payment", fn _ -> :any end, 1)
  #       |> Router.add_path_route("payment.success", fn _ -> :success end, 2)

  #     routes = Router.list_routes(router)
  #     assert Enum.member?(routes, {"payment", :path, 1})
  #     assert Enum.member?(routes, {"payment.success", :path, 2})
  #   end

  #   test "lists pattern routes" do
  #     router =
  #       Router.new()
  #       |> Router.add_pattern_route(
  #         "payment",
  #         fn %Signal{data: %{amount: amount}} -> amount > 1000 end,
  #         fn _ -> :large end,
  #         10
  #       )

  #     routes = Router.list_routes(router)
  #     assert Enum.member?(routes, {"payment", :pattern, 10})
  #   end

  #   test "lists mixed routes" do
  #     router =
  #       Router.new()
  #       |> Router.add_path_route("payment", fn _ -> :any end, 1)
  #       |> Router.add_pattern_route(
  #         "payment",
  #         fn %Signal{data: %{amount: amount}} -> amount > 1000 end,
  #         fn _ -> :large end,
  #         10
  #       )

  #     routes = Router.list_routes(router)
  #     assert Enum.member?(routes, {"payment", :path, 1})
  #     assert Enum.member?(routes, {"payment", :pattern, 10})
  #   end
  # end
end
