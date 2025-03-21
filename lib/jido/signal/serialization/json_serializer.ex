#
# Json Serializer from Commanded: https://github.com/commanded/commanded/blob/master/lib/commanded/serialization/json_serializer.ex
# License: MIT
#
if Code.ensure_loaded?(Jason) do
  defmodule Jido.Signal.Serialization.JsonSerializer do
    @moduledoc """
    A serializer that uses the JSON format and Jason library.
    """

    alias Jido.Signal.Serialization.TypeProvider
    alias Jido.Signal.Serialization.JsonDecoder

    @doc """
    Serialize given term to JSON binary data.
    """
    def serialize(term) do
      Jason.encode!(term)
    end

    @doc """
    Deserialize given JSON binary data to the expected type.
    """
    def deserialize(binary, config \\ [])

    def deserialize(binary, config) do
      {type, opts} =
        case Keyword.get(config, :type) do
          nil ->
            {nil, []}

          type_str ->
            # Check if the module exists before trying to convert to a struct
            module_name = String.to_atom(type_str)

            if Code.ensure_loaded?(module_name) do
              {TypeProvider.to_struct(type_str), [keys: :atoms]}
            else
              raise ArgumentError, "Cannot deserialize to non-existent module: #{type_str}"
            end
        end

      binary
      |> Jason.decode!(opts)
      |> to_struct(type)
      |> JsonDecoder.decode()
    end

    defp to_struct(data, nil), do: data

    defp to_struct(data, struct) when is_atom(struct) do
      # Check if the module exists to prevent UndefinedFunctionError
      if Code.ensure_loaded?(struct) do
        struct(struct, data)
      else
        raise ArgumentError, "Cannot deserialize to non-existent module: #{inspect(struct)}"
      end
    end

    # Handle the case where struct is already a struct type (not a module name)
    defp to_struct(data, %type{} = _struct) do
      struct(type, data)
    end
  end

  # require Protocol

  # Protocol.derive(Jason.Encoder, Commanded.EventStore.SnapshotData)
end
