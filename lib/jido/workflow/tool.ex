defmodule Jido.Action.Tool do
  @moduledoc """
  Provides functionality to convert Jido Workflows into tool representations.

  This module allows Jido Workflows to be easily integrated with AI systems
  like LangChain or Instructor by converting them into a standardized tool format.
  """

  alias Jido.Error

  @type tool :: %{
          name: String.t(),
          description: String.t(),
          function: (map(), map() -> {:ok, String.t()} | {:error, String.t()}),
          parameters_schema: map()
        }

  @doc """
  Converts a Jido Workflow into a tool representation.

  ## Arguments

    * `workflow` - The module implementing the Jido.Action behavior.

  ## Returns

    A map representing the workflow as a tool, compatible with systems like LangChain.

  ## Examples

      iex> tool = Jido.Action.Tool.to_tool(MyWorkflow)
      %{
        name: "my_workflow",
        description: "Performs a specific task",
        function: #Function<...>,
        parameters_schema: %{...}
      }
  """
  @spec to_tool(module()) :: tool()
  def to_tool(workflow) when is_atom(workflow) do
    %{
      name: workflow.name(),
      description: workflow.description(),
      function: &execute_workflow(workflow, &1, &2),
      parameters_schema: build_parameters_schema(workflow.schema())
    }
  end

  @doc """
  Executes an workflow and formats the result for tool output.

  This function is typically used as the function value in the tool representation.
  """
  @spec execute_workflow(module(), map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_workflow(workflow, params, context) do
    case Jido.Workflow.run(workflow, params, context) do
      {:ok, result} ->
        {:ok, Jason.encode!(result)}

      {:error, %Error{} = error} ->
        {:error, Jason.encode!(%{error: inspect(error)})}
    end
  end

  @doc """
  Builds a parameters schema for the tool based on the workflow's schema.

  ## Arguments

    * `schema` - The NimbleOptions schema from the workflow.

  ## Returns

    A map representing the parameters schema in a format compatible with LangChain.
  """
  @spec build_parameters_schema(keyword()) :: map()
  def build_parameters_schema(schema) do
    properties =
      Map.new(schema, fn {key, opts} -> {to_string(key), parameter_to_json_schema(opts)} end)

    required =
      schema
      |> Enum.filter(fn {_key, opts} -> Keyword.get(opts, :required, false) end)
      |> Enum.map(fn {key, _opts} -> to_string(key) end)

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end

  @doc """
  Converts a NimbleOptions parameter definition to a JSON Schema representation.

  ## Arguments

    * `opts` - The options for a single parameter from the NimbleOptions schema.

  ## Returns

    A map representing the parameter in JSON Schema format.
  """
  @spec parameter_to_json_schema(keyword()) :: %{
          type: String.t(),
          description: String.t()
        }
  def parameter_to_json_schema(opts) do
    %{
      type: nimble_type_to_json_schema_type(Keyword.get(opts, :type)),
      description: Keyword.get(opts, :doc, "No description provided.")
    }
  end

  @doc """
  Converts a NimbleOptions type to a JSON Schema type.

  ## Arguments

    * `type` - The NimbleOptions type.

  ## Returns

    A string representing the equivalent JSON Schema type.
  """
  @spec nimble_type_to_json_schema_type(atom()) :: String.t()
  def nimble_type_to_json_schema_type(:string), do: "string"
  def nimble_type_to_json_schema_type(:integer), do: "integer"
  def nimble_type_to_json_schema_type(:float), do: "number"
  def nimble_type_to_json_schema_type(:boolean), do: "boolean"
  def nimble_type_to_json_schema_type(:keyword_list), do: "object"
  def nimble_type_to_json_schema_type(:map), do: "object"
  def nimble_type_to_json_schema_type({:list, _}), do: "array"
  def nimble_type_to_json_schema_type({:map, _}), do: "object"
  def nimble_type_to_json_schema_type(_), do: "string"
end
