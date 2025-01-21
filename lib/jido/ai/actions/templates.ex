defmodule Jido.AI.Actions.Templates do
  @moduledoc """
  Provides type-safe prompt templates with validation, interpolation, and composition.
  """

  @type template :: %{
          name: String.t(),
          description: String.t(),
          template: String.t(),
          variables: [atom()],
          examples: [map()],
          parent: template() | nil,
          options: map()
        }

  @type template_result :: {:ok, String.t()} | {:error, String.t()}

  @options_schema [
    chain_of_thought: [
      type: :boolean,
      default: false,
      doc: "Whether to include chain of thought prompting"
    ],
    few_shot: [
      type: :boolean,
      default: false,
      doc: "Whether to include few-shot examples"
    ],
    max_examples: [
      type: :integer,
      default: 3,
      doc: "Maximum number of examples to include"
    ]
  ]

  @doc """
  Creates a new prompt template with validation.
  """
  @spec create_template(String.t(), String.t(), String.t(), [atom()], keyword()) ::
          {:ok, template()} | {:error, String.t()}
  def create_template(name, description, template_str, variables, opts \\ []) do
    options = Keyword.get(opts, :options, %{})

    if not is_binary(name) do
      {:error, "Name must be a string"}
    else
      case NimbleOptions.validate(Map.to_list(options), @options_schema) do
        {:ok, validated_options} ->
          {:ok,
           %{
             name: name,
             description: description,
             template: template_str,
             variables: variables,
             examples: Keyword.get(opts, :examples, []),
             options: Map.new(validated_options),
             parent: nil
           }}

        {:error, %NimbleOptions.ValidationError{} = error} ->
          {:error, Exception.message(error)}
      end
    end
  end

  @doc """
  Renders a prompt template with the given variables.
  """
  @spec render_template(template(), map()) :: template_result()
  def render_template(template, variables) do
    with :ok <- validate_variables(template.variables, Map.keys(variables)),
         {:ok, base} <- maybe_render_parent(template, variables),
         {:ok, with_examples} <- maybe_add_examples(template, base),
         {:ok, final} <- maybe_add_chain_of_thought(template, with_examples) do
      rendered =
        Enum.reduce(variables, template.template <> final, fn {key, value}, acc ->
          String.replace(acc, "{#{key}}", to_string(value))
        end)

      {:ok, String.trim(rendered)}
    end
  end

  @doc """
  Composes a new template by extending an existing one.
  """
  @spec compose(template(), String.t(), String.t(), String.t(), [atom()], keyword()) ::
          {:ok, template()} | {:error, String.t()}
  def compose(parent, name, description, template_str, variables, opts \\ []) do
    with {:ok, child} <- create_template(name, description, template_str, variables, opts) do
      {:ok, %{child | parent: parent}}
    end
  end

  @doc """
  Updates template options.
  """
  @spec update_options(template(), map()) :: {:ok, template()} | {:error, String.t()}
  def update_options(template, new_options) do
    case NimbleOptions.validate(
           Map.to_list(Map.merge(template.options, new_options)),
           @options_schema
         ) do
      {:ok, validated_options} ->
        {:ok, %{template | options: Map.new(validated_options)}}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Exception.message(error)}
    end
  end

  # Private functions

  defp validate_variables(required, provided) do
    missing = required -- provided

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required variables: #{inspect(missing)}"}
    end
  end

  defp maybe_render_parent(%{parent: nil} = _template, _variables), do: {:ok, ""}

  defp maybe_render_parent(%{parent: parent} = _template, variables) do
    case render_template(parent, variables) do
      {:ok, rendered} -> {:ok, rendered <> "\n\n"}
      error -> error
    end
  end

  defp maybe_add_examples(%{options: %{few_shot: true}} = template, base) do
    examples =
      template.examples
      |> Enum.take(template.options.max_examples)
      |> Enum.map_join("\n\n", fn example ->
        case render_template(%{template | examples: [], options: %{few_shot: false}}, example) do
          {:ok, rendered} -> "Example:\n#{rendered}"
          _ -> ""
        end
      end)

    if examples == "" do
      {:ok, base}
    else
      {:ok, base <> "\n\nHere are some examples:\n" <> examples <> "\n\n"}
    end
  end

  defp maybe_add_examples(_template, base), do: {:ok, base}

  defp maybe_add_chain_of_thought(%{options: %{chain_of_thought: true}}, base) do
    {:ok,
     base <>
       "\n\nLet's solve this step by step:\n" <>
       "1. First, let's understand what we need to do\n" <>
       "2. Then, let's break it down into smaller parts\n" <>
       "3. Finally, let's combine everything"}
  end

  defp maybe_add_chain_of_thought(_template, base), do: {:ok, base}
end
