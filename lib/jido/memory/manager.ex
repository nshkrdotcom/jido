defmodule Jido.Memory.Manager do
  @moduledoc """
  Provides a high-level API for managing memories and knowledge items.
  Handles initialization of the storage adapter and provides a clean interface
  for creating, retrieving, and searching memories.
  """

  use GenServer

  alias Jido.Memory.Types.Memory
  alias Jido.Memory.MemoryAdapter.ETS, as: DefaultAdapter

  @type memory_params :: %{
          user_id: String.t(),
          agent_id: String.t(),
          room_id: String.t(),
          content: String.t(),
          embedding: [float()] | nil
        }

  # Client API

  @doc """
  Starts a new Memory manager process.

  ## Options
    * `:adapter` - The adapter module to use for storage (default: #{DefaultAdapter})
    * `:name` - The name to register the process under
    * Other options are passed to the adapter's init function
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Creates a new memory with the given parameters.
  Returns `{:ok, Memory.t()}` or `{:error, reason}`.
  """
  def create_memory(pid \\ __MODULE__, params) do
    GenServer.call(pid, {:create_memory, params})
  end

  @doc """
  Retrieves a memory by its ID.
  Returns `{:ok, Memory.t() | nil}` or `{:error, reason}`.
  """
  def get_memory_by_id(pid \\ __MODULE__, memory_id) do
    GenServer.call(pid, {:get_memory_by_id, memory_id})
  end

  @doc """
  Retrieves all memories for a given room.
  Returns `{:ok, [Memory.t()]}` or `{:error, reason}`.
  """
  def get_memories(pid \\ __MODULE__, room_id, opts \\ []) do
    GenServer.call(pid, {:get_memories, room_id, opts})
  end

  @doc """
  Searches for memories similar to the given query.
  Returns `{:ok, [Memory.t()]}` or `{:error, reason}`.
  """
  def search_similar_memories(pid \\ __MODULE__, _query, query_embedding, opts \\ []) do
    GenServer.call(pid, {:search_memories, query_embedding, opts})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    adapter = Keyword.get(opts, :adapter, DefaultAdapter)
    name = Keyword.get(opts, :name, __MODULE__)

    case validate_adapter(adapter) do
      :ok ->
        case adapter.init([name: name] ++ opts) do
          {:ok, adapter_state} ->
            {:ok, %{adapter: adapter, adapter_state: adapter_state}}

          {:error, reason} ->
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, {:invalid_adapter, reason}}
    end
  end

  @impl true
  def handle_call(
        {:create_memory, params},
        _from,
        %{adapter: adapter, adapter_state: state} = data
      ) do
    with {:ok, validated} <- validate_memory_params(params),
         memory =
           struct!(
             Memory,
             Map.merge(validated, %{
               id: generate_id(),
               created_at: DateTime.utc_now()
             })
           ),
         {:ok, created} <- adapter.create_memory(memory, state) do
      {:reply, {:ok, created}, data}
    else
      {:error, reason} -> {:reply, {:error, reason}, data}
    end
  end

  def handle_call(
        {:get_memory_by_id, memory_id},
        _from,
        %{adapter: adapter, adapter_state: state} = data
      ) do
    result = adapter.get_memory_by_id(memory_id, state)
    {:reply, result, data}
  end

  def handle_call(
        {:get_memories, room_id, opts},
        _from,
        %{adapter: adapter, adapter_state: state} = data
      ) do
    result = adapter.get_memories(room_id, opts, state)
    {:reply, result, data}
  end

  def handle_call(
        {:search_memories, query_embedding, opts},
        _from,
        %{adapter: adapter, adapter_state: state} = data
      ) do
    result = adapter.search_memories_by_embedding(query_embedding, opts, state)
    {:reply, result, data}
  end

  # Private Helpers

  defp validate_adapter(adapter) do
    with {:module, _} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :init, 1),
         true <- function_exported?(adapter, :create_memory, 2),
         true <- function_exported?(adapter, :get_memory_by_id, 2),
         true <- function_exported?(adapter, :get_memories, 3),
         true <- function_exported?(adapter, :search_memories_by_embedding, 3),
         true <- function_exported?(adapter, :create_knowledge, 2),
         true <- function_exported?(adapter, :search_knowledge_by_embedding, 3) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :missing_callbacks}
    end
  end

  defp validate_memory_params(params) do
    required_keys = [:user_id, :agent_id, :room_id, :content]

    if Enum.all?(required_keys, &Map.has_key?(params, &1)) do
      validated =
        params
        |> Map.take(required_keys ++ [:embedding])
        |> Map.new()

      {:ok, validated}
    else
      {:error, :invalid_params}
    end
  end

  defp generate_id do
    "mem_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
