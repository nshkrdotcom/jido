defmodule Jido do
  @moduledoc """
  Jido is a flexible framework for building distributed AI Agents and Workflows in Elixir.

  This module provides the main interface for interacting with Jido components, including:
  - Managing and interacting with Agents through a high-level API
  - Listing and retrieving Actions, Sensors, and Domains
  - Filtering and paginating results
  - Generating unique slugs for components

  ## Agent Interaction Examples

      # Find and act on an agent
      "agent-id"
      |> Jido.get_agent_by_id()
      |> Jido.act(:command, %{param: "value"})

      # Act asynchronously
      {:ok, agent} = Jido.get_agent_by_id("agent-id")
      Jido.act_async(agent, :command)

      # Send management commands
      {:ok, agent} = Jido.get_agent_by_id("agent-id")
      Jido.manage(agent, :pause)

      # Subscribe to agent events
      {:ok, topic} = Jido.get_agent_topic("agent-id")
      Phoenix.PubSub.subscribe(MyApp.PubSub, topic)
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
        |> Keyword.put_new(:agent_registry, Jido.AgentRegistry)
      end

      # Get the configured agent registry
      def agent_registry, do: config()[:agent_registry]

      # Provide a child spec so we can be placed directly under a Supervisor
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

      # Delegate high-level API methods to Jido module
      defdelegate get_agent_by_id(id), to: Jido
      defdelegate act(agent, command, params \\ %{}), to: Jido
      defdelegate act_async(agent, command, params \\ %{}), to: Jido
      defdelegate manage(agent, command, params \\ %{}), to: Jido
      defdelegate get_agent_topic(agent_or_id), to: Jido
    end
  end

  @doc """
  Retrieves a running Agent by its ID.

  ## Parameters

  - `id`: String or atom ID of the agent to retrieve
  - `opts`: Optional keyword list of options:
    - `:registry`: Override the default agent registry

  ## Returns

  - `{:ok, pid}` if agent is found and running
  - `{:error, :not_found}` if agent doesn't exist

  ## Examples

      iex> {:ok, agent} = Jido.get_agent_by_id("my-agent")
      {:ok, #PID<0.123.0>}

      # Using a custom registry
      iex> {:ok, agent} = Jido.get_agent_by_id("my-agent", registry: MyApp.Registry)
      {:ok, #PID<0.123.0>}
  """
  @spec get_agent_by_id(String.t() | atom(), keyword()) :: {:ok, pid()} | {:error, :not_found}
  def get_agent_by_id(id, opts \\ []) when is_binary(id) or is_atom(id) do
    registry = opts[:registry] || Jido.AgentRegistry

    case Registry.lookup(registry, id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Pipe-friendly version of get_agent_by_id that raises on errors.

  ## Parameters

  - `id`: String or atom ID of the agent to retrieve
  - `opts`: Optional keyword list of options:
    - `:registry`: Override the default agent registry

  ## Returns

  - `pid` if agent is found
  - Raises `RuntimeError` if agent not found

  ## Examples

      iex> "my-agent" |> Jido.get_agent_by_id!() |> Jido.act(:command)
      :ok
  """
  @spec get_agent_by_id!(String.t() | atom(), keyword()) :: pid()
  def get_agent_by_id!(id, opts \\ []) do
    case get_agent_by_id(id, opts) do
      {:ok, pid} -> pid
      {:error, :not_found} -> raise "Agent not found: #{id}"
    end
  end

  @doc """
  Sends a synchronous action command to an agent.

  ## Parameters

  - `agent`: Agent pid or return value from get_agent_by_id
  - `command`: The command to execute
  - `params`: Optional map of command parameters

  ## Returns

  Returns the result of command execution.

  ## Examples

      iex> {:ok, agent} = Jido.get_agent_by_id("my-agent")
      iex> Jido.act(agent, :generate_response, %{prompt: "Hello"})
      {:ok, %{response: "Hi there!"}}
  """
  @spec act(pid() | {:ok, pid()}, atom(), map()) :: any()
  def act({:ok, pid}, command, params), do: act(pid, command, params)

  def act(pid, command, params) when is_pid(pid) do
    Jido.Agent.Runtime.act(pid, command, params)
  end

  @doc """
  Sends an asynchronous action command to an agent.

  ## Parameters

  - `agent`: Agent pid or return value from get_agent_by_id
  - `command`: The command to execute
  - `params`: Optional map of command parameters

  ## Returns

  - `:ok` if command was accepted
  - `{:error, reason}` if rejected

  ## Examples

      iex> {:ok, agent} = Jido.get_agent_by_id("my-agent")
      iex> Jido.act_async(agent, :generate_response, %{prompt: "Hello"})
      :ok
  """
  @spec act_async(pid() | {:ok, pid()}, atom(), map()) :: :ok | {:error, term()}
  def act_async({:ok, pid}, command, params), do: act_async(pid, command, params)

  def act_async(pid, command, params) when is_pid(pid) do
    Jido.Agent.Runtime.act_async(pid, command, params)
  end

  @doc """
  Sends a management command to an agent.

  ## Parameters

  - `agent`: Agent pid or return value from get_agent_by_id
  - `command`: The command to execute
  - `params`: Optional map of command parameters

  ## Returns

  Returns the result of command execution.

  ## Examples

      iex> {:ok, agent} = Jido.get_agent_by_id("my-agent")
      iex> Jido.manage(agent, :pause)
      :ok
  """
  @spec manage(pid() | {:ok, pid()}, atom(), map()) :: any()
  def manage({:ok, pid}, command, params), do: manage(pid, command, params)

  def manage(pid, command, params) when is_pid(pid) do
    Jido.Agent.Runtime.manage(pid, command, params)
  end

  @doc """
  Gets the PubSub topic for an agent.

  ## Parameters

  - `agent_or_id`: Agent pid, ID, or return value from get_agent_by_id

  ## Returns

  - `{:ok, topic}` with the agent's topic string
  - `{:error, reason}` if topic couldn't be retrieved

  ## Examples

      iex> {:ok, topic} = Jido.get_agent_topic("my-agent")
      {:ok, "jido.agent.my-agent"}

      iex> {:ok, agent} = Jido.get_agent_by_id("my-agent")
      iex> {:ok, topic} = Jido.get_agent_topic(agent)
      {:ok, "jido.agent.my-agent"}
  """
  @spec get_agent_topic(pid() | {:ok, pid()} | String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_agent_topic({:ok, pid}), do: get_agent_topic(pid)

  def get_agent_topic(pid) when is_pid(pid) do
    Jido.Agent.Runtime.get_topic(pid)
  end

  def get_agent_topic(id) when is_binary(id) or is_atom(id) do
    case get_agent_by_id(id) do
      {:ok, pid} -> get_agent_topic(pid)
      error -> error
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

  # Component Discovery
  defdelegate list_actions(opts \\ []), to: Jido.Discovery
  defdelegate list_sensors(opts \\ []), to: Jido.Discovery
  defdelegate list_agents(opts \\ []), to: Jido.Discovery
  defdelegate list_commands(opts \\ []), to: Jido.Discovery

  defdelegate get_action_by_slug(slug), to: Jido.Discovery
  defdelegate get_sensor_by_slug(slug), to: Jido.Discovery
  defdelegate get_agent_by_slug(slug), to: Jido.Discovery
  defdelegate get_command_by_slug(slug), to: Jido.Discovery
end
