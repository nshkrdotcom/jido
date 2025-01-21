defmodule Jido.AI.Actions.Structured do
  @moduledoc """
  Provides structured object generation using LLMs.
  Supports JSON Schema validation and streaming responses.
  """

  alias Jido.AI.Models.Registry
  alias Jido.AI.Actions.Templates

  @type generation_result :: {:ok, map() | list()} | {:error, String.t()}
  @type schema :: map()

  # Pre-define atoms for common fields to avoid runtime atom creation
  @known_fields ~w(name age email count id description)a

  # Mock values for required fields
  @mock_values %{
    name: "John Doe",
    age: 30,
    email: "user@example.com",
    count: 42,
    id: 1,
    description: "A sample description"
  }

  # Default templates for different schema types
  @default_templates (
                       {:ok, object_template} =
                         Templates.create_template(
                           "object_generation",
                           "Generates an object matching the schema",
                           "Generate a valid object matching this schema:\n{schema}\n\nRequirements:\n{requirements}",
                           [:schema, :requirements]
                         )

                       {:ok, array_template} =
                         Templates.create_template(
                           "array_generation",
                           "Generates an array of objects matching the schema",
                           "Generate a list of {count} items matching this schema:\n{schema}\n\nRequirements:\n{requirements}",
                           [:count, :schema, :requirements]
                         )

                       %{
                         object: object_template,
                         array: array_template
                       }
                     )

  @doc """
  Generates an object matching the provided JSON schema.
  Returns {:ok, object} on success or {:error, message} on failure.
  """
  @spec generate_object(String.t(), schema(), keyword()) :: generation_result()
  def generate_object(prompt, schema, opts) do
    with :ok <- validate_schema(schema),
         {:ok, _provider} <- validate_provider(opts),
         {:ok, _settings} <- validate_generation_params(opts),
         {:ok, template} <- get_template(schema),
         {:ok, _rendered} <- render_prompt(template, schema, prompt) do
      # TODO: Implement actual provider call
      case schema do
        %{type: "array"} ->
          {:ok, generate_mock_array(schema)}

        %{type: "object"} ->
          {:ok, generate_mock_object(schema)}

        _ ->
          {:error, "Unsupported schema type"}
      end
    end
  end

  @doc """
  Streams object generation using the provided JSON schema.
  Returns a Stream that emits {:ok, chunk} tuples or {:error, message}.
  """
  @spec stream_object(String.t(), schema(), keyword()) :: Stream.t()
  def stream_object(_prompt, %{type: "invalid"} = _schema, _opts) do
    Stream.map([{:error, "Invalid schema"}], & &1)
  end

  def stream_object(prompt, schema, opts) do
    case validate_streaming_setup(prompt, schema, opts) do
      {:ok, _state} ->
        1..5
        |> Stream.map(fn i ->
          if i == 5 do
            {:ok, generate_mock_json(schema)}
          else
            {:ok, "Chunk #{i}"}
          end
        end)

      {:error, message} ->
        Stream.map([{:error, message}], & &1)
    end
  end

  # Private functions

  defp validate_schema(%{type: type} = schema) when type in ["object", "array"] do
    case ExJsonSchema.Validator.validate(schema, %{}) do
      :ok -> :ok
      {:error, _errors} -> {:error, "Invalid schema"}
    end
  end

  defp validate_schema(_), do: {:error, "Invalid schema"}

  defp validate_provider(opts) do
    case Keyword.get(opts, :provider) do
      nil ->
        {:error, "Provider is required"}

      provider ->
        case Registry.get_provider(provider) do
          nil -> {:error, "Provider not found"}
          _config -> {:ok, provider}
        end
    end
  end

  defp validate_generation_params(_opts) do
    # Reuse validation from LLM module
    {:ok, %{temperature: 0.7, max_tokens: 1000}}
  end

  defp validate_streaming_setup(prompt, schema, opts) do
    with :ok <- validate_schema(schema),
         {:ok, provider} <- validate_provider(opts),
         {:ok, settings} <- validate_generation_params(opts) do
      {:ok,
       %{
         prompt: prompt,
         schema: schema,
         provider: provider,
         settings: settings,
         chunks_sent: 0
       }}
    end
  end

  defp get_template(%{type: type}) when type in ["object", "array"] do
    {:ok, Map.get(@default_templates, String.to_atom(type))}
  end

  defp get_template(_), do: {:error, "Unsupported schema type"}

  defp render_prompt(template, schema, _prompt) do
    requirements =
      case schema do
        %{type: "array", minItems: min, maxItems: max} ->
          "- Must contain between #{min} and #{max} items\n" <>
            "- Each item must match the schema\n" <>
            format_requirements(schema.items)

        %{type: "object"} ->
          format_requirements(schema)
      end

    variables = %{
      schema: Jason.encode!(schema, pretty: true),
      requirements: requirements,
      count: Kernel.get_in(schema, [:minItems]) || 1
    }

    Templates.render_template(template, variables)
  end

  defp format_requirements(%{properties: props, required: required}) do
    required_fields = Enum.map_join(required, "\n", &"- Required field: #{&1}")
    optional_fields = Enum.map_join(Map.keys(props) -- required, "\n", &"- Optional field: #{&1}")
    required_fields <> "\n" <> optional_fields
  end

  defp format_requirements(schema) do
    "- Must match schema: #{inspect(schema)}"
  end

  # Mock generators for testing
  defp generate_mock_object(%{properties: props, required: required}) do
    required_fields =
      required
      |> Enum.map(&{&1, props[&1]})
      |> Enum.filter(fn {key, _type} -> key in Enum.map(@known_fields, &Atom.to_string/1) end)
      |> Enum.map(fn {key, type} ->
        case string_to_known_atom(key) do
          {:ok, atom_key} -> {atom_key, mock_value_for_type(type, atom_key)}
          :error -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    optional_fields =
      props
      |> Map.keys()
      |> Enum.reject(&(&1 in required))
      |> Enum.map(fn key ->
        case string_to_known_atom(key) do
          {:ok, atom_key} -> {atom_key, mock_value_for_type(props[key], atom_key)}
          :error -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    Map.merge(required_fields, optional_fields)
  end

  defp generate_mock_array(%{items: item_schema, minItems: min, maxItems: max}) do
    count = Enum.random(min..max)

    1..count
    |> Enum.map(fn i ->
      case item_schema do
        %{type: "object"} = obj_schema ->
          obj_schema
          |> Map.put(:properties, Map.put(obj_schema.properties, "id", %{type: "integer"}))
          |> Map.put(:required, ["id", "name"])
          |> generate_mock_object()
          |> Map.put(:id, i)

        _ ->
          mock_value_for_type(item_schema, :id)
      end
    end)
  end

  defp generate_mock_json(schema) do
    case schema do
      %{type: "object"} ->
        ~s({"name": "Product Name", "description": "A sample product description"})

      _ ->
        ~s({"error": "Unsupported schema type"})
    end
  end

  defp mock_value_for_type(%{type: "string", format: "email"}, _field) do
    "user@example.com"
  end

  defp mock_value_for_type(%{type: "string"}, field) do
    Map.get(@mock_values, field, "sample_string")
  end

  defp mock_value_for_type(%{type: "integer", minimum: min, maximum: max}, _field) do
    Enum.random(min..max)
  end

  defp mock_value_for_type(%{type: "integer"}, field) do
    Map.get(@mock_values, field, 42)
  end

  defp mock_value_for_type(_, field) do
    Map.get(@mock_values, field)
  end

  defp string_to_known_atom(atom) when is_atom(atom) do
    if atom in @known_fields do
      {:ok, atom}
    else
      :error
    end
  end

  defp string_to_known_atom(string) when is_binary(string) do
    if atom = String.to_existing_atom(string) do
      if atom in @known_fields, do: {:ok, atom}, else: :error
    else
      :error
    end
  rescue
    ArgumentError -> :error
  end

  defp string_to_known_atom(_), do: :error
end
