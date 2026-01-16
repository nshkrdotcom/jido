defmodule Jido.Agent.Persistence do
  @moduledoc """
  Persistence facade for agent hibernation and thawing.

  This module provides a clean API for persisting and restoring agent state
  using pluggable storage backends. It handles the serialization (dump) and
  deserialization (load) of agents, delegating to agent-specific callbacks
  when available.

  ## Configuration

  Persistence is configured with a keyword list:

  - `:store` - `{StoreModule, opts}` tuple (required)
  - `:key_fun` - Custom key function `(agent_module, agent_id) -> key` (optional)

  ## Agent Callbacks

  Agents may implement optional callbacks for custom serialization:

  - `dump(agent, context)` - Returns `{:ok, serializable_data}` or `{:error, reason}`
  - `load(data, context)` - Returns `{:ok, agent}` or `{:error, reason}`

  If not implemented, the agent struct is persisted directly.

  ## Examples

      # Configure persistence
      persistence_config = [
        store: {Jido.Agent.Store.ETS, table: :agent_cache}
      ]

      # Hibernate an agent
      :ok = Jido.Agent.Persistence.hibernate(persistence_config, MyAgent, "user-123", agent)

      # Thaw an agent
      case Jido.Agent.Persistence.thaw(persistence_config, MyAgent, "user-123") do
        {:ok, agent} -> agent
        :not_found -> start_fresh_agent()
        {:error, reason} -> handle_error(reason)
      end
  """

  require Logger

  @type config :: keyword()
  @type agent_module :: module()
  @type key :: term()
  @type store_key :: term()

  @doc """
  Persists an agent's state to the configured store.

  Calls the agent's `dump/2` callback if implemented, otherwise persists
  the agent struct directly.

  ## Parameters

  - `config` - Persistence configuration `[store: {Module, opts}, ...]`
  - `agent_module` - The agent module (used for key generation and dump callback)
  - `key` - The unique identifier for this agent instance
  - `agent` - The agent struct to persist

  ## Returns

  - `:ok` - Successfully persisted
  - `{:error, reason}` - Failed to persist

  ## Examples

      :ok = Persistence.hibernate(config, MyAgent, "user-123", agent)
  """
  @spec hibernate(config(), agent_module(), key(), struct()) :: :ok | {:error, term()}
  def hibernate(config, agent_module, key, agent) do
    {store_module, store_opts} = Keyword.fetch!(config, :store)
    store_key = make_store_key(config, agent_module, key)

    case dump_agent(agent_module, agent) do
      {:ok, dump} ->
        case store_module.put(store_key, dump, store_opts) do
          :ok ->
            Logger.debug("Persistence hibernated agent for key #{inspect(key)}")
            :ok

          {:error, reason} ->
            Logger.error(
              "Persistence store.put failed for key #{inspect(key)}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Persistence dump failed for key #{inspect(key)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Loads an agent's state from the configured store.

  Calls the agent's `load/2` callback if implemented, otherwise returns
  the stored data directly (assumed to be the agent struct).

  ## Parameters

  - `config` - Persistence configuration `[store: {Module, opts}, ...]`
  - `agent_module` - The agent module (used for key generation and load callback)
  - `key` - The unique identifier for this agent instance

  ## Returns

  - `{:ok, agent}` - Successfully loaded
  - `:not_found` - No persisted state exists
  - `{:error, reason}` - Failed to load

  ## Examples

      case Persistence.thaw(config, MyAgent, "user-123") do
        {:ok, agent} -> agent
        :not_found -> nil
        {:error, reason} -> handle_error(reason)
      end
  """
  @spec thaw(config(), agent_module(), key()) :: {:ok, struct()} | :not_found | {:error, term()}
  def thaw(config, agent_module, key) do
    {store_module, store_opts} = Keyword.fetch!(config, :store)
    store_key = make_store_key(config, agent_module, key)

    case store_module.get(store_key, store_opts) do
      {:ok, dump} ->
        case load_agent(agent_module, dump) do
          {:ok, agent} ->
            Logger.debug("Persistence thawed agent for key #{inspect(key)}")
            {:ok, agent}

          {:error, reason} ->
            Logger.warning(
              "Persistence failed to load agent for key #{inspect(key)}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      :not_found ->
        :not_found

      {:error, reason} ->
        Logger.warning("Persistence store.get failed for key #{inspect(key)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Serializes an agent for storage.

  If the agent module implements `dump/2`, calls it.
  Otherwise returns the agent struct directly.

  ## Examples

      {:ok, data} = Persistence.dump_agent(MyAgent, agent)
  """
  @spec dump_agent(agent_module(), struct()) :: {:ok, term()} | {:error, term()}
  def dump_agent(agent_module, agent) do
    if function_exported?(agent_module, :dump, 2) do
      agent_module.dump(agent, %{})
    else
      {:ok, agent}
    end
  end

  @doc """
  Deserializes an agent from storage.

  If the agent module implements `load/2`, calls it.
  Otherwise returns the data directly (assumed to be the agent struct).

  ## Examples

      {:ok, agent} = Persistence.load_agent(MyAgent, data)
  """
  @spec load_agent(agent_module(), term()) :: {:ok, struct()} | {:error, term()}
  def load_agent(agent_module, dump) do
    if function_exported?(agent_module, :load, 2) do
      agent_module.load(dump, %{})
    else
      {:ok, dump}
    end
  end

  @doc """
  Generates the store key for an agent instance.

  If `:key_fun` is provided in config, calls it with `(agent_module, key)`.
  Otherwise returns `{agent_module, key}`.

  ## Examples

      key = Persistence.make_store_key(config, MyAgent, "user-123")
      # => {MyAgent, "user-123"}

      config_with_fun = [store: {...}, key_fun: fn mod, k -> "\#{mod}:\#{k}" end]
      key = Persistence.make_store_key(config_with_fun, MyAgent, "user-123")
      # => "Elixir.MyAgent:user-123"
  """
  @spec make_store_key(config(), agent_module(), key()) :: store_key()
  def make_store_key(config, agent_module, key) do
    case Keyword.get(config, :key_fun) do
      nil -> {agent_module, key}
      fun when is_function(fun, 2) -> fun.(agent_module, key)
    end
  end
end
