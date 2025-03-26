defmodule JidoTest.Actions.ReqTest do
  use JidoTest.Case, async: false
  alias Jido.Actions.ReqAction

  # Import Mimic for mocking
  import Mimic

  setup :set_mimic_global

  # Example with custom transform_result
  defmodule SolPrice do
    use ReqAction,
      name: "sol_price",
      description: "Get the price of SOL",
      url: "https://cryptoprices.cc/SOL/",
      method: :get,
      schema: []

    # Override the transform_result function to extract specific data
    @impl Jido.Actions.ReqAction
    def transform_result(_result) do
      # In a real implementation, you would parse the response body
      # For testing, we'll just return a simulated price
      {:ok, %{price: 123.45}}
    end
  end

  # Example without custom transform_result
  defmodule SimpleGet do
    use ReqAction,
      name: "simple_get",
      description: "Simple GET request example",
      url: "https://example.com/api",
      method: :get,
      schema: []

    # No transform_result implementation - will use default
  end

  setup :verify_on_exit!

  test "req action validates and stores configuration" do
    assert SolPrice.name() == "sol_price"
    assert SolPrice.description() == "Get the price of SOL"

    assert SimpleGet.name() == "simple_get"
    assert SimpleGet.description() == "Simple GET request example"
  end

  test "req action with custom transform executes and transforms results" do
    # Create a mock response
    mock_response = %{
      status: 200,
      body: %{"price" => 123.45},
      headers: %{"content-type" => "application/json"}
    }

    # Mock Req.request! to return our mock response
    expect(Req, :request!, fn _opts -> mock_response end)

    # Call run without mock_response in context
    assert {:ok, result} = SolPrice.run(%{}, %{})
    assert is_map(result)
    assert result.price == 123.45
  end

  test "req action without custom transform returns standard result format" do
    # Create a mock response
    mock_response = %{
      status: 200,
      body: %{"data" => "example response"},
      headers: %{"content-type" => "application/json"}
    }

    # Mock Req.request! to return our mock response
    expect(Req, :request!, fn _opts -> mock_response end)

    # Call run without mock_response in context
    assert {:ok, result} = SimpleGet.run(%{}, %{})
    assert is_map(result)
    assert result.request.url == "https://example.com/api"
    assert result.request.method == :get
    assert result.response.status == 200
    assert result.response.body == %{"data" => "example response"}
  end
end
