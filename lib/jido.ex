defmodule Jido do
  @moduledoc """
  Jido enables intelligent automation in Elixir, with a focus on Actions, Workflows, Bots, Agents, Sensors, and Signals for creating dynamic and adaptive systems.
  """
  use Jido.Util, debug_enabled: false

  @doc """
  Retrieves all loaded Action modules and their metadata.

  This function scans all loaded modules and identifies those that are Actions
  by checking for the presence of the `__action_metadata__/0` function.
  It then collects the metadata for each Action.

  ## Returns

  A list of tuples, where each tuple contains:
  - The module name of the Action
  - The metadata of the Action as returned by `__action_metadata__/0`

  ## Examples

      iex> Jido.Action.all_actions()
      [
        {MyApp.SomeAction, [name: "some_action", description: "Does something"]},
        {MyApp.AnotherAction, [name: "another_action", description: "Does something else"]}
      ]

  """
  def get_action_by_slug(slug) do
    Enum.find(list_actions(), fn action -> action.slug == slug end)
  end

  def get_sensor_by_slug(slug) do
    Enum.find(list_sensors(), fn sensor -> sensor.slug == slug end)
  end

  def get_domain_by_slug(slug) do
    Enum.find(list_domains(), fn domain -> domain.slug == slug end)
  end

  @spec list_actions(keyword()) :: [{module(), map()}]
  def list_actions(opts \\ []) do
    debug("Listing actions with options", opts: opts)
    list_modules(opts, :__action_metadata__)
  end

  @spec list_sensors(keyword()) :: [{module(), map()}]
  def list_sensors(opts \\ []) do
    debug("Listing sensors with options", opts: opts)
    list_modules(opts, :__sensor_metadata__)
  end

  @spec list_domains(keyword()) :: [{module(), map()}]
  def list_domains(opts \\ []) do
    debug("Listing domains with options", opts: opts)
    list_modules(opts, :__domain_metadata__)
  end

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

  defp all_applications do
    Application.loaded_applications()
    |> Enum.map(fn {app, _description, _version} -> app end)
  end

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

  defp has_metadata_function?(module, function) do
    result = Code.ensure_loaded?(module) and function_exported?(module, function, 0)
    debug("Metadata function check result", module: module, function: function, result: result)
    result
  end

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
