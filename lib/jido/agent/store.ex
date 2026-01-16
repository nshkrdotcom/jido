defmodule Jido.Agent.Store do
  @moduledoc """
  Behaviour for agent state persistence.

  Implement this behaviour to create custom storage backends for agent
  hibernate/thaw functionality. The store is used by `Jido.Agent.InstanceManager` to
  persist agent state when idle and restore it on demand.

  ## Built-in Adapters

  - `Jido.Agent.Store.ETS` - Fast, in-memory, not restart-safe (dev/test)
  - `Jido.Agent.Store.File` - Simple file-based, restart-safe

  ## Example Implementation

      defmodule MyApp.RedisStore do
        @behaviour Jido.Agent.Store

        @impl true
        def get(key, opts) do
          case Redix.command(:redix, ["GET", serialize_key(key)]) do
            {:ok, nil} -> :not_found
            {:ok, data} -> {:ok, :erlang.binary_to_term(data)}
            {:error, reason} -> {:error, reason}
          end
        end

        @impl true
        def put(key, dump, opts) do
          ttl = Keyword.get(opts, :ttl, 3600)
          data = :erlang.term_to_binary(dump)
          case Redix.command(:redix, ["SETEX", serialize_key(key), ttl, data]) do
            {:ok, "OK"} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end

        @impl true
        def delete(key, opts) do
          case Redix.command(:redix, ["DEL", serialize_key(key)]) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end

        defp serialize_key({module, id}), do: "agent:\#{module}:\#{id}"
      end
  """

  @type key :: term()
  @type dump :: term()
  @type opts :: keyword()

  @doc """
  Retrieves a persisted agent state by key.

  Returns `{:ok, dump}` if found, `:not_found` if not present,
  or `{:error, reason}` on failure.
  """
  @callback get(key(), opts()) :: {:ok, dump()} | :not_found | {:error, term()}

  @doc """
  Persists agent state under the given key.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @callback put(key(), dump(), opts()) :: :ok | {:error, term()}

  @doc """
  Deletes persisted agent state by key.

  Returns `:ok` on success (including if key didn't exist) or `{:error, reason}` on failure.
  """
  @callback delete(key(), opts()) :: :ok | {:error, term()}
end
