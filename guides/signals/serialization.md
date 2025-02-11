# Signal Serialization

## Overview

Jido's signal serialization system enables reliable data persistence and transmission across process boundaries. The implementation draws inspiration from the [Commanded](https://github.com/commanded/commanded) package's event serialization approach, with proper attribution and licensing compliance.

## Core Components

### JsonSerializer

The `JsonSerializer` module handles the conversion of signals and their data payloads to and from JSON format. It supports:

- Automatic type encoding/decoding
- Custom serialization handlers
- Nested data structures
- Efficient binary encoding

### Type Providers

Type providers maintain the mapping between Elixir structs and their serialized representations:

```elixir
defmodule ModuleNameTypeProvider do
  @doc """
  Converts a struct to its type string representation.
  """
  def to_string(%struct{}) do
    struct |> Module.split() |> Enum.join(".")
  end

  @doc """
  Converts a type string back to its struct module.
  """
  def to_struct(type_string) do
    type_string
    |> String.split(".")
    |> Module.safe_concat()
    |> struct()
  end
end
```

## Basic Usage

### Serializing Signals

```elixir
# Create a signal
signal = %Jido.Signal{
  type: "user.created",
  data: %UserCreated{id: "123", email: "user@example.com"}
}

# Serialize to JSON string
{:ok, json} = Jido.Signal.JsonSerializer.serialize(signal)
```

### Deserializing Signals

```elixir
# Deserialize from JSON string
{:ok, signal} = Jido.Signal.JsonSerializer.deserialize(json)
```

## Custom Decoders

Implement the `JsonDecoder` behaviour to customize how your structs are deserialized:

```elixir
defmodule MyCustomStruct do
  @behaviour Jido.Signal.JsonDecoder

  def decode(data) do
    # Custom deserialization logic
    %__MODULE__{
      field: transform_field(data.field)
    }
  end
end
```

## Advanced Features

### Nested Data Structures

The serializer handles complex nested data structures automatically:

```elixir
# Nested data example
signal = %Jido.Signal{
  type: "order.created",
  data: %OrderCreated{
    order: %Order{
      items: [
        %OrderItem{product_id: "123", quantity: 2},
        %OrderItem{product_id: "456", quantity: 1}
      ]
    }
  }
}

# Serializes and deserializes nested structures
{:ok, json} = JsonSerializer.serialize(signal)
{:ok, deserialized} = JsonSerializer.deserialize(json)
```

### Binary Data Handling

For binary data, use base64 encoding:

```elixir
defmodule BinaryData do
  defstruct [:content]

  def encode(%__MODULE__{content: content}) do
    Base.encode64(content)
  end

  def decode(encoded) do
    Base.decode64!(encoded)
  end
end
```

## Best Practices

1. **Type Safety**

   - Always specify types explicitly
   - Use custom decoders for complex transformations
   - Validate data during deserialization

2. **Error Handling**

   - Handle deserialization errors gracefully
   - Provide meaningful error messages
   - Implement fallback strategies

3. **Performance**
   - Cache type mappings when possible
   - Minimize unnecessary transformations
   - Use streaming for large datasets

## Common Pitfalls

### Type Mismatches

```elixir
# Wrong
signal = Signal.new(%{
  type: "user.created",
  data: raw_map  # Missing type information
})

# Right
signal = Signal.new(%{
  type: "user.created",
  data: %UserCreated{} = UserCreated.from_map(raw_map)
})
```

### Missing Decoders

```elixir
# Will fail without decoder
defmodule ComplexStruct do
  defstruct [:special_field]
end

# Implement decoder for reliable deserialization
defmodule ComplexStruct do
  defstruct [:special_field]
  @behaviour JsonDecoder

  def decode(data) do
    %__MODULE__{special_field: data.special_field}
  end
end
```

## Testing

Always test serialization/deserialization roundtrips:

```elixir
defmodule SerializationTest do
  use ExUnit.Case

  test "roundtrip serialization" do
    original = %MyStruct{field: "value"}
    {:ok, json} = JsonSerializer.serialize(original)
    {:ok, deserialized} = JsonSerializer.deserialize(json)
    assert deserialized == original
  end
end
```

## See Also

- [Signal Overview](signals/overview.md)
- [Type System](core/types.md)
- [Testing Guide](guides/testing.md)

## Attribution

The serialization system's design draws inspiration from the [Commanded](https://github.com/commanded/commanded) package (MIT License), particularly its event serialization approach. We acknowledge and thank the Commanded team for their excellent work.
