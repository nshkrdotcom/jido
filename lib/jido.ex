defmodule Jido do
  @moduledoc """
  Jido is a flexible framework for building distributed AI Agents and Workflows in Elixir.  It enables intelligent automation in Elixir, with a focus on Actions, Workflows, Bots, Agents, Sensors, and Signals for creating dynamic and adaptive systems.

  This module provides the main interface for interacting with Jido components, including:
  - Listing and retrieving Actions, Sensors, and Domains
  - Filtering and paginating results
  - Generating unique slugs for components

  ## Examples

      iex> Jido.list_actions()
      [%{module: MyApp.SomeAction, name: "some_action", description: "Does something", slug: "abc123de"}]

      iex> Jido.get_action_by_slug("abc123de")
      %{module: MyApp.SomeAction, name: "some_action", description: "Does something", slug: "abc123de"}

  """
  use Jido.Util, debug_enabled: false

  @type component_metadata :: %{
          module: module(),
          name: String.t(),
          description: String.t(),
          slug: String.t(),
          category: atom() | nil,
          tags: [atom()] | nil
        }

  @doc """
  Retrieves an Action by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Action.

  ## Returns

  The Action metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_action_by_slug("abc123de")
      %{module: MyApp.SomeAction, name: "some_action", description: "Does something", slug: "abc123de"}

      iex> Jido.get_action_by_slug("nonexistent")
      nil

  """
  @spec get_action_by_slug(String.t()) :: component_metadata() | nil
  def get_action_by_slug(slug) do
    Enum.find(list_actions(), fn action -> action.slug == slug end)
  end

  @doc """
  Retrieves a Sensor by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Sensor.

  ## Returns

  The Sensor metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_sensor_by_slug("def456gh")
      %{module: MyApp.SomeSensor, name: "some_sensor", description: "Monitors something", slug: "def456gh"}

      iex> Jido.get_sensor_by_slug("nonexistent")
      nil

  """
  @spec get_sensor_by_slug(String.t()) :: component_metadata() | nil
  def get_sensor_by_slug(slug) do
    Enum.find(list_sensors(), fn sensor -> sensor.slug == slug end)
  end

  @doc """
  Retrieves a Domain by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Domain.

  ## Returns

  The Domain metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_domain_by_slug("ghi789jk")
      %{module: MyApp.SomeDomain, name: "some_domain", description: "Represents a domain", slug: "ghi789jk"}

      iex> Jido.get_domain_by_slug("nonexistent")
      nil

  """
  @spec get_domain_by_slug(String.t()) :: component_metadata() | nil
  def get_domain_by_slug(slug) do
    Enum.find(list_domains(), fn domain -> domain.slug == slug end)
  end

  @doc """
  Lists all Actions with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Actions by name (partial match).
    - `:description`: Filter Actions by description (partial match).
    - `:category`: Filter Actions by category (exact match).
    - `:tag`: Filter Actions by tag (must have the exact tag).

  ## Returns

  A list of Action metadata.

  ## Examples

      iex> Jido.list_actions(limit: 10, offset: 5, category: :utility)
      [%{module: MyApp.SomeAction, name: "some_action", description: "Does something", slug: "abc123de", category: :utility}]

  """
  @spec list_actions(keyword()) :: [component_metadata()]
  def list_actions(opts \\ []) do
    debug("Listing actions with options", opts: opts)
    list_modules(opts, :__action_metadata__)
  end

  @doc """
  Lists all Sensors with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Sensors by name (partial match).
    - `:description`: Filter Sensors by description (partial match).
    - `:category`: Filter Sensors by category (exact match).
    - `:tag`: Filter Sensors by tag (must have the exact tag).

  ## Returns

  A list of Sensor metadata.

  ## Examples

      iex> Jido.list_sensors(limit: 10, offset: 5, category: :monitoring)
      [%{module: MyApp.SomeSensor, name: "some_sensor", description: "Monitors something", slug: "def456gh", category: :monitoring}]

  """
  @spec list_sensors(keyword()) :: [component_metadata()]
  def list_sensors(opts \\ []) do
    debug("Listing sensors with options", opts: opts)
    list_modules(opts, :__sensor_metadata__)
  end

  @doc """
  Lists all Domains with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Domains by name (partial match).
    - `:description`: Filter Domains by description (partial match).
    - `:category`: Filter Domains by category (exact match).
    - `:tag`: Filter Domains by tag (must have the exact tag).

  ## Returns

  A list of Domain metadata.

  ## Examples

      iex> Jido.list_domains(limit: 10, offset: 5, category: :business)
      [%{module: MyApp.SomeDomain, name: "some_domain", description: "Represents a domain", slug: "ghi789jk", category: :business}]

  """
  @spec list_domains(keyword()) :: [component_metadata()]
  def list_domains(opts \\ []) do
    debug("Listing domains with options", opts: opts)
    list_modules(opts, :__domain_metadata__)
  end

  # Private functions

  @spec list_modules(keyword(), atom()) :: [component_metadata()]
  defp list_modules(opts, metadata_function) do
    debug("Listing modules", opts: opts, metadata_function: metadata_function)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)
    name_filter = Keyword.get(opts, :name)
    description_filter = Keyword.get(opts, :description)
    category_filter = Keyword.get(opts, :category)
    tag_filter = Keyword.get(opts, :tag)

    debug("Filters applied",
      limit: limit,
      offset: offset,
      name: name_filter,
      description: description_filter,
      category: category_filter,
      tag: tag_filter
    )

    result =
      all_applications()
      |> Enum.flat_map(&all_modules/1)
      |> Enum.filter(&has_metadata_function?(&1, metadata_function))
      |> Enum.map(fn module ->
        metadata = apply(module, metadata_function, [])
        module_name = to_string(module)

        slug =
          :sha256
          |> :crypto.hash(module_name)
          |> Base.url_encode64(padding: false)
          |> String.slice(0, 8)

        metadata
        |> Map.put(:module, module)
        |> Map.put(:slug, slug)
      end)
      |> Enum.filter(fn metadata ->
        filter_metadata(metadata, name_filter, description_filter, category_filter, tag_filter)
      end)
      |> Enum.drop(offset)
      |> maybe_limit(limit)

    debug("Modules listed", count: length(result))
    result
  end

  @spec all_applications() :: [atom()]
  defp all_applications do
    Application.loaded_applications()
    |> Enum.map(fn {app, _description, _version} -> app end)
  end

  @spec all_modules(atom()) :: [module()]
  defp all_modules(app) do
    debug("Fetching all modules")

    case :application.get_key(app, :modules) do
      {:ok, modules} ->
        debug("Modules fetched", count: length(modules))
        modules

      :undefined ->
        debug("No modules found for #{app} application")
        []
    end
  end

  @spec has_metadata_function?(module(), atom()) :: boolean()
  defp has_metadata_function?(module, function) do
    result = Code.ensure_loaded?(module) and function_exported?(module, function, 0)
    debug("Metadata function check result", module: module, function: function, result: result)
    result
  end

  @spec filter_metadata(map(), String.t() | nil, String.t() | nil, atom() | nil, atom() | nil) ::
          boolean()
  defp filter_metadata(metadata, name, description, category, tag) do
    debug("Filtering metadata",
      metadata: metadata,
      name: name,
      description: description,
      category: category,
      tag: tag
    )

    name_match = is_nil(name) or String.contains?(metadata[:name] || "", name)

    description_match =
      is_nil(description) or String.contains?(metadata[:description] || "", description)

    category_match = is_nil(category) or metadata[:category] == category
    tag_match = is_nil(tag) or (is_list(metadata[:tags]) and tag in metadata[:tags])

    result = name_match and description_match and category_match and tag_match
    debug("Filter result", result: result)
    result
  end

  @spec maybe_limit(list(), non_neg_integer() | nil) :: list()
  defp maybe_limit(list, nil) do
    debug("No limit applied to list")
    list
  end

  defp maybe_limit(list, limit) when is_integer(limit) and limit > 0 do
    debug("Applying limit to list", limit: limit)
    Enum.take(list, limit)
  end

  defp maybe_limit(list, _) do
    debug("Invalid limit, returning original list")
    list
  end
end
