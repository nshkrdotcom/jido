defmodule Jido.AI.Actions.StructuredTest do
  use JidoTest.Case, async: true

  alias Jido.AI.Actions.Structured

  describe "object_generation" do
    test "generates object matching schema" do
      schema = %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          age: %{type: "integer"},
          email: %{type: "string", format: "email"}
        },
        required: ["name", "age", "email"]
      }

      result = Structured.generate_object("Create a user profile", schema, provider: :anthropic)
      assert {:ok, object} = result
      assert is_map(object)
      assert is_binary(object.name)
      assert is_integer(object.age)
      assert String.contains?(object.email, "@")
    end

    test "validates against schema" do
      schema = %{
        type: "object",
        properties: %{
          count: %{type: "integer", minimum: 0, maximum: 100}
        },
        required: ["count"]
      }

      result = Structured.generate_object("Generate a count", schema, provider: :anthropic)
      assert {:ok, object} = result
      assert object.count >= 0
      assert object.count <= 100
    end

    test "handles invalid schema" do
      schema = %{type: "invalid"}
      result = Structured.generate_object("Test prompt", schema, provider: :anthropic)
      assert {:error, message} = result
      assert message =~ "Invalid schema"
    end

    test "handles missing provider" do
      schema = %{type: "object", properties: %{}}
      result = Structured.generate_object("Test prompt", schema, [])
      assert {:error, message} = result
      assert message =~ "Provider is required"
    end
  end

  describe "array_generation" do
    test "generates array of objects" do
      schema = %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            id: %{type: "integer"},
            name: %{type: "string"}
          },
          required: ["id", "name"]
        },
        minItems: 2,
        maxItems: 5
      }

      result =
        Structured.generate_object("Generate a list of items", schema, provider: :anthropic)

      assert {:ok, items} = result
      assert is_list(items)
      assert length(items) >= 2
      assert length(items) <= 5
      assert Enum.all?(items, &(is_integer(&1.id) and is_binary(&1.name)))
    end
  end

  describe "streaming" do
    test "streams object generation" do
      schema = %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          description: %{type: "string"}
        },
        required: ["name", "description"]
      }

      stream = Structured.stream_object("Generate a product", schema, provider: :anthropic)
      assert is_struct(stream, Stream)

      chunks = Enum.take(stream, 5)
      assert length(chunks) > 0
      assert Enum.all?(chunks, &match?({:ok, _}, &1))

      # Last chunk should be valid JSON
      {:ok, last_chunk} = List.last(chunks)
      assert {:ok, object} = Jason.decode(last_chunk)
      assert is_binary(object["name"])
      assert is_binary(object["description"])
    end

    test "handles streaming errors" do
      schema = %{type: "invalid"}
      stream = Structured.stream_object("Test prompt", schema, provider: :anthropic)
      assert [{:error, message}] = Enum.take(stream, 1)
      assert message =~ "Invalid schema"
    end
  end
end
