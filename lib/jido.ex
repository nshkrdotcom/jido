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

  @callback config() :: keyword()

  defmacro __using__(opts) do
    quote do
      @behaviour unquote(__MODULE__)
      @otp_app unquote(opts)[:otp_app] ||
                 raise(ArgumentError, """
                 You must provide `otp_app: :your_app` to use Jido, e.g.:

                     use Jido, otp_app: :my_app
                 """)

      # Public function to retrieve config from application environment
      def config do
        Application.get_env(@otp_app, __MODULE__, [])
      end

      # Provide a child spec so we can be placed directly under a Supervisor:
      @spec child_spec(any()) :: Supervisor.child_spec()
      def child_spec(_arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []},
          shutdown: 5000,
          type: :supervisor
        }
      end

      # Entry point for starting the Jido supervisor
      @spec start_link() :: Supervisor.on_start()
      def start_link do
        unquote(__MODULE__).ensure_started(__MODULE__)
      end
    end
  end

  @doc """
  Callback used by the generated `start_link/0` function.
  This is where we actually call Jido.Supervisor.start_link.
  """
  @spec ensure_started(module()) :: Supervisor.on_start()
  def ensure_started(jido_module) do
    config = jido_module.config()
    Jido.Supervisor.start_link(jido_module, config)
  end

  @doc """
  Retrieves a prompt file from the priv/prompts directory by its name.

  ## Parameters

  - `name`: An atom representing the name of the prompt file (without .txt extension)

  ## Returns

  The contents of the prompt file as a string if found, otherwise raises an error.

  ## Examples

      iex> Jido.prompt(:system)
      "You are a helpful AI assistant..."

      iex> Jido.prompt(:nonexistent)
      ** (File.Error) could not read file priv/prompts/nonexistent.txt

  """
  @spec prompt(atom()) :: String.t()
  def prompt(name) when is_atom(name) do
    app = Application.get_application(__MODULE__)
    path = :code.priv_dir(app)
    prompt_path = Path.join([path, "prompts", "#{name}.txt"])
    File.read!(prompt_path)
  end

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
    Enum.find(list_agents(), fn agent -> agent.slug == slug end)
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
    list_modules(opts, :__agent_metadata__)
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

    result =
      matches_name?(metadata, name) and
        matches_description?(metadata, description) and
        matches_category?(metadata, category) and
        matches_tag?(metadata, tag)

    debug("Filter result", result: result)
    result
  end

  defp matches_name?(_metadata, nil), do: true

  defp matches_name?(metadata, name) do
    String.contains?(metadata[:name] || "", name)
  end

  defp matches_description?(_metadata, nil), do: true

  defp matches_description?(metadata, description) do
    String.contains?(metadata[:description] || "", description)
  end

  defp matches_category?(_metadata, nil), do: true

  defp matches_category?(metadata, category) do
    metadata[:category] == category
  end

  defp matches_tag?(_metadata, nil), do: true

  defp matches_tag?(metadata, tag) do
    is_list(metadata[:tags]) and tag in metadata[:tags]
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
