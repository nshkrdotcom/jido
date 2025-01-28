defmodule Jido.Memory.AdapterBehaviour do
  @moduledoc """
  Defines the adapter behaviour for storing and querying Jido memories.
  """

  alias Jido.Memory.Types.{Memory, KnowledgeItem}

  @doc """
  Initialize the adapter with the given options.
  Returns `{:ok, state}` or `{:error, reason}`.
  """
  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Create a new memory entry.
  Returns `{:ok, Memory}` or `{:error, reason}`.
  """
  @callback create_memory(memory :: Memory.t(), state :: any()) ::
              {:ok, Memory.t()} | {:error, reason :: any()}

  @doc """
  Retrieve a memory by its ID.
  Returns `{:ok, Memory | nil}` or `{:error, reason}`.
  """
  @callback get_memory_by_id(memory_id :: term(), state :: any()) ::
              {:ok, Memory.t() | nil} | {:error, reason :: any()}

  @doc """
  Retrieve memories for a given room ID with optional filters.
  Returns `{:ok, [Memory]}` or `{:error, reason}`.
  """
  @callback get_memories(room_id :: term(), opts :: keyword(), state :: any()) ::
              {:ok, [Memory.t()]} | {:error, reason :: any()}

  @doc """
  Search memories using an embedding vector.
  Returns `{:ok, [Memory]}` or `{:error, reason}`.
  """
  @callback search_memories_by_embedding(
              embedding :: [float()],
              opts :: keyword(),
              state :: any()
            ) ::
              {:ok, [Memory.t()]} | {:error, reason :: any()}

  @doc """
  Create a new knowledge item.
  Returns `{:ok, KnowledgeItem}` or `{:error, reason}`.
  """
  @callback create_knowledge(item :: KnowledgeItem.t(), state :: any()) ::
              {:ok, KnowledgeItem.t()} | {:error, reason :: any()}

  @doc """
  Search knowledge items using an embedding vector.
  Returns `{:ok, [KnowledgeItem]}` or `{:error, reason}`.
  """
  @callback search_knowledge_by_embedding(
              embedding :: [float()],
              opts :: keyword(),
              state :: any()
            ) ::
              {:ok, [KnowledgeItem.t()]} | {:error, reason :: any()}
end
