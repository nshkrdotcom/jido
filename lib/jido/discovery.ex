defmodule Jido.Discovery do
  @moduledoc """
  Discovery is the mechanism by which agents and sensors are discovered and registered with the system.

  This module caches discovered components using :persistent_term for efficient lookups.
  The cache is initialized at application startup and can be manually refreshed if needed.
  """
  use Jido.Util, debug_enabled: false
  require Logger

  @cache_key :__jido_discovery_cache__
  @cache_version "1.0"

  @type component_type :: :action | :sensor | :command | :agent
  @type component_metadata :: %{
          module: module(),
          name: String.t(),
          description: String.t(),
          slug: String.t(),
          category: atom() | nil,
          tags: [atom()] | nil
        }

  @type cache_entry :: %{
          version: String.t(),
          last_updated: DateTime.t(),
          actions: [component_metadata()],
          sensors: [component_metadata()],
          # commands: [component_metadata()],
          agents: [component_metadata()]
        }

  @doc """
  Initializes the discovery cache. Should be called during application startup.

  ## Returns

  - `:ok` if cache was initialized successfully
  - `{:error, reason}` if initialization failed
  """
  @spec init() :: :ok | {:error, term()}
  def init do
    debug("Initializing discovery cache")

    try do
      cache = build_cache()
      :persistent_term.put(@cache_key, cache)
      Logger.info("Jido discovery cache initialized successfully")
      :ok
    rescue
      e ->
        Logger.warning("Failed to initialize Jido discovery cache: #{inspect(e)}")
        {:error, :cache_init_failed}
    end
  end

  @doc """
  Forces a refresh of the discovery cache.

  ## Returns

  - `:ok` if cache was refreshed successfully
  - `{:error, reason}` if refresh failed
  """
  @spec refresh() :: :ok | {:error, term()}
  def refresh do
    debug("Refreshing discovery cache")

    try do
      cache = build_cache()
      :persistent_term.put(@cache_key, cache)
      Logger.info("Jido discovery cache refreshed successfully")
      :ok
    rescue
      e ->
        Logger.warning("Failed to refresh Jido discovery cache: #{inspect(e)}")
        {:error, :cache_refresh_failed}
    end
  end

  @doc """
  Gets the last time the cache was updated.

  ## Returns

  - `{:ok, datetime}` with the last update time
  - `{:error, :not_initialized}` if cache hasn't been initialized
  """
  @spec last_updated() :: {:ok, DateTime.t()} | {:error, :not_initialized}
  def last_updated do
    case get_cache() do
      {:ok, cache} -> {:ok, cache.last_updated}
      error -> error
    end
  end

  @doc false
  def __get_cache__, do: get_cache()

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
    with {:ok, cache} <- get_cache() do
      Enum.find(cache.actions, fn action -> action.slug == slug end)
    else
      _ -> nil
    end
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
    with {:ok, cache} <- get_cache() do
      Enum.find(cache.sensors, fn sensor -> sensor.slug == slug end)
    else
      _ -> nil
    end
  end

  @doc """
  Retrieves an Agent by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Agent.

  ## Returns

  The Agent metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_agent_by_slug("ghi789jk")
      %{module: MyApp.SomeAgent, name: "some_agent", description: "Represents an agent", slug: "ghi789jk"}

      iex> Jido.get_agent_by_slug("nonexistent")
      nil

  """
  @spec get_agent_by_slug(String.t()) :: component_metadata() | nil
  def get_agent_by_slug(slug) do
    with {:ok, cache} <- get_cache() do
      Enum.find(cache.agents, fn agent -> agent.slug == slug end)
    else
      _ -> nil
    end
  end

  @doc """
  Retrieves a Command by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Command.

  ## Returns

  The Command metadata if found, otherwise `nil`.

  ## Examples

      iex> Jido.get_command_by_slug("jkl012mn")
      %{module: MyApp.SomeCommand, name: "some_command", description: "Executes something", slug: "jkl012mn"}

      iex> Jido.get_command_by_slug("nonexistent")
      nil

  """
  @spec get_command_by_slug(String.t()) :: component_metadata() | nil
  def get_command_by_slug(slug) do
    with {:ok, cache} <- get_cache() do
      Enum.find(cache.commands, fn command -> command.slug == slug end)
    else
      _ -> nil
    end
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

    with {:ok, cache} <- get_cache() do
      filter_and_paginate(cache.actions, opts)
    else
      _ -> []
    end
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

    with {:ok, cache} <- get_cache() do
      filter_and_paginate(cache.sensors, opts)
    else
      _ -> []
    end
  end

  @doc """
  Lists all Commands with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.

  ## Returns

  A list of Command metadata.

  ## Examples

      iex> Jido.list_commands(limit: 10, offset: 5, category: :business)
      [%{module: MyApp.SomeCommand, name: "some_command", description: "Represents a command", slug: "ghi789jk", category: :business}]

  """
  @spec list_commands(keyword()) :: [component_metadata()]
  def list_commands(opts \\ []) do
    debug("Listing commands with options", opts: opts)

    with {:ok, cache} <- get_cache() do
      filter_and_paginate(cache.commands, opts)
    else
      _ -> []
    end
  end

  @doc """
  Lists all Agents with optional filtering and pagination.

  ## Parameters

  - `opts`: A keyword list of options for filtering and pagination. Available options:
    - `:limit`: Maximum number of results to return.
    - `:offset`: Number of results to skip before starting to return.
    - `:name`: Filter Agents by name (partial match).
    - `:description`: Filter Agents by description (partial match).
    - `:category`: Filter Agents by category (exact match).
    - `:tag`: Filter Agents by tag (must have the exact tag).

  ## Returns

  A list of Agent metadata.

  ## Examples

      iex> Jido.list_agents(limit: 10, offset: 5, category: :business)
      [%{module: MyApp.SomeAgent, name: "some_agent", description: "Represents an agent", slug: "ghi789jk", category: :business}]

  """
  @spec list_agents(keyword()) :: [component_metadata()]
  def list_agents(opts \\ []) do
    debug("Listing agents with options", opts: opts)

    with {:ok, cache} <- get_cache() do
      filter_and_paginate(cache.agents, opts)
    else
      _ -> []
    end
  end

  # Private functions

  defp get_cache do
    try do
      case :persistent_term.get(@cache_key) do
        %{version: @cache_version} = cache -> {:ok, cache}
        _ -> {:error, :invalid_cache_version}
      end
    rescue
      ArgumentError -> {:error, :not_initialized}
    end
  end

  defp build_cache do
    %{
      version: @cache_version,
      last_updated: DateTime.utc_now(),
      actions: discover_components(:__action_metadata__),
      sensors: discover_components(:__sensor_metadata__),
      commands: discover_components(:__command_metadata__),
      agents: discover_components(:__agent_metadata__)
    }
  end

  defp discover_components(metadata_function) do
    debug("Discovering components", metadata_function: metadata_function)

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

      # Special handling for command metadata which returns command specs
      metadata =
        case metadata_function do
          :__command_metadata__ ->
            debug("Processing command metadata", metadata: metadata)
            # Extract command names, handling both keyword lists and lists with bare atoms
            command_names =
              metadata
              |> Enum.map(fn
                {name, _opts} when is_atom(name) -> name
                name when is_atom(name) -> name
                {name, _opts} when is_tuple(name) -> elem(name, 0)
              end)

            debug("Extracted command names", names: command_names)

            # Convert to map, handling both keyword lists and lists with bare atoms
            commands_map =
              metadata
              |> Enum.map(fn
                {name, opts} when is_atom(name) -> {name, opts}
                name when is_atom(name) -> {name, [description: "Command #{name}", schema: []]}
                {name, opts} when is_tuple(name) -> {elem(name, 0), opts}
              end)
              |> Map.new()

            %{
              name: module_name |> String.split(".") |> List.last() |> Macro.underscore(),
              description: "Command module providing: #{Enum.join(command_names, ", ")}",
              category: :command,
              tags: command_names,
              commands: commands_map
            }

          _ ->
            if Keyword.keyword?(metadata), do: Map.new(metadata), else: metadata
        end

      metadata
      |> Map.put(:module, module)
      |> Map.put(:slug, slug)
    end)
  end

  defp filter_and_paginate(components, opts) do
    components
    |> filter_components(opts)
    |> paginate(opts)
  end

  defp filter_components(components, opts) do
    name = Keyword.get(opts, :name)
    description = Keyword.get(opts, :description)
    category = Keyword.get(opts, :category)
    tag = Keyword.get(opts, :tag)

    Enum.filter(components, fn metadata ->
      matches_name?(metadata, name) and
        matches_description?(metadata, description) and
        matches_category?(metadata, category) and
        matches_tag?(metadata, tag)
    end)
  end

  defp paginate(components, opts) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit)

    components
    |> Enum.drop(offset)
    |> maybe_limit(limit)
  end

  defp all_applications,
    do: Application.loaded_applications() |> Enum.map(fn {app, _, _} -> app end)

  defp all_modules(app) do
    case :application.get_key(app, :modules) do
      {:ok, modules} -> modules
      :undefined -> []
    end
  end

  defp has_metadata_function?(module, function) do
    Code.ensure_loaded?(module) and function_exported?(module, function, 0)
  end

  defp matches_name?(_metadata, nil), do: true
  defp matches_name?(metadata, name), do: String.contains?(metadata[:name] || "", name)

  defp matches_description?(_metadata, nil), do: true

  defp matches_description?(metadata, description),
    do: String.contains?(metadata[:description] || "", description)

  defp matches_category?(_metadata, nil), do: true
  defp matches_category?(metadata, category), do: metadata[:category] == category

  defp matches_tag?(_metadata, nil), do: true
  defp matches_tag?(metadata, tag), do: is_list(metadata[:tags]) and tag in metadata[:tags]

  defp maybe_limit(list, nil), do: list
  defp maybe_limit(list, limit) when is_integer(limit) and limit > 0, do: Enum.take(list, limit)
  defp maybe_limit(list, _), do: list
end
