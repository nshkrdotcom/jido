# defmodule Jido.Agent.ServerNew do
#   use GenServer
#   use ExDbug, enabled: false

#   alias Jido.Agent.Server.Execute
#   alias Jido.Agent.Server.PubSub
#   alias Jido.Agent.Server.Signal, as: ServerSignal
#   alias Jido.Agent.Server.State, as: ServerState
#   alias Jido.Signal

#   require Logger

#   @default_max_queue_size 10_000
#   @queue_check_interval 10_000

#   @type start_opt ::
#           {:agent, struct() | module()}
#           | {:pubsub, module()}
#           | {:name, String.t() | atom()}
#           | {:topic, String.t()}
#           | {:max_queue_size, pos_integer()}
#           | {:registry, module()}

#   def start_link(opts) do
#     with {:ok, agent} <- build_agent(opts),
#          {:ok, agent} <- validate_agent(agent),
#          {:ok, config} <- build_config(opts, agent) do
#       dbug("Starting Agent", name: config.name, pubsub: config.pubsub, topic: config.topic)

#       GenServer.start_link(
#         __MODULE__,
#         %{
#           agent: agent,
#           pubsub: config.pubsub,
#           topic: config.topic,
#           max_queue_size: config.max_queue_size
#         },
#         name: via_tuple(config.name, config.registry)
#       )
#     end
#   end

#   @doc false
#   def child_spec(opts) do
#     dbug("Creating child spec", opts: opts)
#     id = Keyword.get(opts, :id, __MODULE__)

#     %{
#       id: id,
#       start: {__MODULE__, :start_link, [opts]},
#       shutdown: 5000,
#       restart: :permanent,
#       type: :worker
#     }
#   end

#   def get_state(server) do
#     GenServer.call(server, ServerSignal.get_state())
#   end

#   def init(state) do
#     {:ok, state}
#   end

#   def handle_call(ServerSignal.get_state(), _from, state) do
#     {:reply, state, state}
#   end

#   def handle_call(request, from, state) do
#     {:reply, {:error, :not_implemented}, state}
#   end

#   def handle_cast(request, state) do
#     {:noreply, state}
#   end

#   def handle_info(request, state) do
#     {:noreply, state}
#   end

#   def terminate(reason, %ServerState{child_supervisor: supervisor} = state)
#       when is_pid(supervisor) do
#     dbug("Server terminating",
#       reason: inspect(reason),
#       agent_id: state.agent.id,
#       status: state.status
#     )

#     with :ok <- PubSub.emit_event(state, ServerSignal.stopped(), %{reason: reason}),
#          :ok <- cleanup_processes(supervisor),
#          :ok <- Enum.each([state.topic | state.subscriptions], &PubSub.unsubscribe(state, &1)) do
#       :ok
#     else
#       _error ->
#         error("Cleanup failed during termination")
#         :ok
#     end
#   end

#   def terminate(_reason, _state), do: :ok

#   defp build_agent(opts) do
#     case Keyword.fetch(opts, :agent) do
#       {:ok, agent_input} when not is_nil(agent_input) ->
#         if is_atom(agent_input) and :erlang.function_exported(agent_input, :new, 0) do
#           {:ok, agent_input.new()}
#         else
#           {:ok, agent_input}
#         end

#       _ ->
#         {:error, :invalid_agent}
#     end
#   end

#   defp build_config(opts, agent) do
#     try do
#       {:ok,
#        %{
#          name: opts[:name] || agent.id,
#          pubsub: Keyword.fetch!(opts, :pubsub),
#          topic: Keyword.get(opts, :topic, PubSub.generate_topic(agent.id)),
#          max_queue_size: Keyword.get(opts, :max_queue_size, @default_max_queue_size),
#          registry: Keyword.get(opts, :registry, Jido.AgentRegistry)
#        }}
#     rescue
#       KeyError -> {:error, :missing_pubsub}
#     end
#   end

#   defp validate_agent(agent) when is_map(agent) and is_binary(agent.id), do: {:ok, agent}
#   defp validate_agent(_), do: {:error, :invalid_agent}

#   defp via_tuple(name, registry), do: {:via, Registry, {registry, name}}
# end
