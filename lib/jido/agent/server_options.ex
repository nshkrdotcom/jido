defmodule Jido.Agent.Server.Options do
  use ExDbug, enabled: false
  @decorate_all dbug()

  @server_state_opts_schema NimbleOptions.new!(
                              id: [
                                type: :string,
                                required: true,
                                doc: "The unique identifier for an instance of an Agent."
                              ],
                              agent: [
                                type: {:custom, __MODULE__, :validate_agent_opts, []},
                                required: true,
                                doc: "The Agent struct or module to be managed by this server"
                              ],
                              mode: [
                                type: {:in, [:auto, :step]},
                                default: :auto,
                                doc: "Server execution mode"
                              ],
                              log_level: [
                                type: {:in, [:debug, :info, :warn, :error]},
                                default: :info,
                                doc: "Logging verbosity level"
                              ],
                              max_queue_size: [
                                type: :non_neg_integer,
                                default: 10_000,
                                doc: "Maximum number of signals that can be queued"
                              ],
                              registry: [
                                type: :atom,
                                default: Jido.AgentRegistry,
                                doc: "Registry to register the server process with"
                              ],
                              output: [
                                type: {:custom, __MODULE__, :validate_output_opts, []},
                                default: [
                                  out: {:logger, [level: :info]},
                                  err: {:logger, [level: :error]},
                                  log: {:logger, [level: :debug]}
                                ],
                                doc: "Dispatch configuration for signal routing"
                              ],
                              routes: [
                                type: {:custom, __MODULE__, :validate_route_opts, []},
                                default: [],
                                doc:
                                  "Route specifications for signal routing. Can be a single Route struct, list of Route structs, or list of route spec tuples"
                              ],
                              sensors: [
                                type: {:list, :mod_arg},
                                default: [],
                                doc: "List of sensor modules to load"
                              ],
                              skills: [
                                type: {:list, :atom},
                                default: [],
                                doc: "List of skill modules to load"
                              ],
                              child_specs: [
                                type: {:list, :mod_arg},
                                default: [],
                                doc: "List of child specs to start when the agent is mounted"
                              ]
                            )

  @doc """
  Builds a validated ServerState struct from the provided options.

  ## Parameters

  - `opts` - Keyword list of server options

  ## Returns

  - `{:ok, state}` - Successfully built state
  - `{:error, reason}` - Failed to build state

  ## Example

      iex> Jido.Agent.Server.Options.build_state(
      ...>   agent: agent,
      ...>   name: "agent_1",
      ...>   routes: [{"example.event", signal}],
      ...>   skills: [WeatherSkill],
      ...> )
      {:ok, %ServerState{...}}
  """
  def validate_server_opts(opts) do
    case NimbleOptions.validate(opts, @server_state_opts_schema) do
      {:ok, validated_opts} ->
        {:ok,
         [
           agent: validated_opts[:agent],
           output: validated_opts[:output],
           routes: validated_opts[:routes],
           skills: validated_opts[:skills],
           child_specs: validated_opts[:child_specs],
           log_level: validated_opts[:log_level],
           mode: validated_opts[:mode],
           registry: validated_opts[:registry],
           max_queue_size: validated_opts[:max_queue_size]
         ]}

      {:error, error} ->
        {:error, error}
    end
  end

  def validate_agent_opts(agent, _opts \\ []) do
    cond do
      is_atom(agent) ->
        {:ok, agent}

      is_struct(agent) and function_exported?(agent.__struct__, :new, 2) ->
        {:ok, agent}

      true ->
        {:error, :invalid_agent}
    end
  end

  def validate_output_opts(output, _opts \\ []) do
    out_config = validate_output_dispatch(output[:out])
    err_config = validate_output_dispatch(output[:err])
    log_config = validate_output_dispatch(output[:log])

    {:ok,
     [
       out: out_config,
       err: err_config,
       log: log_config
     ]}
  end

  defp validate_output_dispatch(nil), do: {:console, []}

  defp validate_output_dispatch(config) do
    case Jido.Signal.Dispatch.validate_opts(config) do
      {:ok, validated} -> validated
      {:error, _reason} -> {:console, []}
    end
  end

  def validate_route_opts(routes, _opts \\ []) do
    case Jido.Signal.Router.normalize(routes) do
      {:ok, normalized} ->
        case Jido.Signal.Router.validate(normalized) do
          {:ok, validated} ->
            {:ok, validated}

          {:error, reason} when is_binary(reason) ->
            {:error, reason}

          {:error, reason} ->
            {:error, "Invalid route configuration: #{inspect(reason)}"}
        end

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "Invalid route format: #{inspect(reason)}"}
    end
  end
end
