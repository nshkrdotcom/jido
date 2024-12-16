defmodule Jido.Agent.Supervisor do
  @moduledoc """
  A dynamic supervisor that manages agent workers and their associated processes.

  Each agent worker runs under this supervisor and can dynamically start/stop
  additional child processes. The supervisor provides:

  - Dynamic agent worker management
  - Named process registration via Registry
  - Child process supervision
  - Telemetry instrumentation
  - Configurable restart strategies
  """

  use DynamicSupervisor
  use Jido.Util, debug_enabled: false
  require Logger

  @type init_opts :: [{:name, atom()} | {:pubsub, module()}]
  @type supervisor_opts :: [
          strategy: :one_for_one,
          max_restarts: non_neg_integer(),
          max_seconds: non_neg_integer()
        ]
  @type child_spec :: :supervisor.child_spec() | {module(), term()} | module()

  @telemetry_prefix [:jido, :agent, :supervisor]

  # Client API

  def start_link(opts \\ []) do
    debug("Starting Jido.Agent.Supervisor with opts: #{inspect(opts)}")
    name = Keyword.get(opts, :name, __MODULE__)
    pubsub = Keyword.get(opts, :pubsub, Application.get_env(:jido, :pubsub, TestPubSub))
    Application.put_env(:jido, :pubsub, pubsub)
    debug("Using PubSub: #{inspect(pubsub)}")
    result = DynamicSupervisor.start_link(__MODULE__, opts, name: name)
    debug("Jido.Agent.Supervisor start result: #{inspect(result)}")
    result
  end

  @spec start_agent(Jido.Agent.t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(agent, opts \\ []) do
    debug("Starting agent with id: #{agent.id}, opts: #{inspect(opts)}")
    start_time = System.monotonic_time()
    name = opts[:name] || agent.id
    pubsub = Application.get_env(:jido, :pubsub)

    spec =
      {Jido.Agent.Worker,
       Keyword.merge(opts,
         agent: agent,
         name: name,
         pubsub: pubsub
       )}

    debug("Starting child with spec: #{inspect(spec)}")
    result = DynamicSupervisor.start_child(__MODULE__, spec)
    debug("Agent start result: #{inspect(result)}")

    :telemetry.execute(
      @telemetry_prefix ++ [:agent, :start],
      %{duration: System.monotonic_time() - start_time},
      %{agent_id: agent.id, result: result}
    )

    result
  end

  @spec start_child(child_spec(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_child(child_spec, opts \\ []) do
    debug("Starting child with spec: #{inspect(child_spec)}, opts: #{inspect(opts)}")

    case normalize_child_spec(child_spec, opts) do
      {:ok, spec} ->
        debug("Normalized child spec: #{inspect(spec)}")
        result = DynamicSupervisor.start_child(__MODULE__, spec)
        debug("Child start result: #{inspect(result)}")
        result

      {:error, _} = error ->
        debug("Error normalizing child spec: #{inspect(error)}")
        error
    end
  end

  @spec terminate_child(pid()) :: :ok | {:error, :not_found}
  def terminate_child(pid) do
    debug("Terminating child with pid: #{inspect(pid)}")
    result = DynamicSupervisor.terminate_child(__MODULE__, pid)
    debug("Child termination result: #{inspect(result)}")
    result
  end

  @spec which_children() :: [{:undefined, pid() | :restarting, :worker | :supervisor, [module()]}]
  def which_children do
    debug("Fetching children")
    children = DynamicSupervisor.which_children(__MODULE__)
    debug("Current children: #{inspect(children)}")
    children
  end

  @spec find_agent(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def find_agent(id) do
    debug("Looking up agent with id: #{id}")

    case Registry.lookup(Jido.AgentRegistry, id) do
      [{pid, _}] ->
        debug("Found agent with pid: #{inspect(pid)}")
        {:ok, pid}

      [] ->
        debug("No agent found with id: #{id}")
        {:error, :not_found}
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    debug("Initializing Jido.Agent.Supervisor")

    init_result =
      DynamicSupervisor.init(
        strategy: :one_for_one,
        max_restarts: 3,
        max_seconds: 1,
        extra_arguments: []
      )

    debug("Initialization result: #{inspect(init_result)}")
    init_result
  end

  # Private Functions

  defp normalize_child_spec(module, opts) when is_atom(module) do
    debug("Normalizing child spec for module: #{inspect(module)}, opts: #{inspect(opts)}")
    normalize_child_spec({module, opts}, [])
  end

  defp normalize_child_spec({module, args}, _opts) when is_atom(module) do
    debug("Normalizing child spec for module: #{inspect(module)}, args: #{inspect(args)}")

    spec =
      {:ok,
       %{
         id: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
         start: {module, :start_link, [args]},
         restart: :transient
       }}

    debug("Normalized child spec: #{inspect(spec)}")
    spec
  end
end
