defmodule Jido.Memory.Knowledge do
  @moduledoc """
  Manages long-term knowledge items, including preprocessing, chunking,
  and semantic search capabilities.
  """

  use GenServer

  alias Jido.Memory.Types.KnowledgeItem
  alias Jido.Memory.MemoryAdapter.ETS, as: DefaultAdapter

  @type knowledge_params :: %{
          agent_id: String.t(),
          content: String.t(),
          metadata: map() | nil,
          embedding: [float()] | nil
        }

  @default_chunk_size 512

  # Client API

  @doc """
  Starts a new Knowledge manager process.

  ## Options
    * `:adapter` - The adapter module to use for storage (default: #{DefaultAdapter})
    * `:name` - The name to register the process under
    * `:chunk_size` - Maximum size for content chunks (default: #{@default_chunk_size})
    * Other options are passed to the adapter's init function
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Creates one or more knowledge items from the given parameters.
  If the content is large, it will be split into chunks.
  Returns `{:ok, KnowledgeItem.t() | [KnowledgeItem.t()]}` or `{:error, reason}`.
  """
  def create_knowledge(pid \\ __MODULE__, params) do
    GenServer.call(pid, {:create_knowledge, params})
  end

  @doc """
  Searches for knowledge items similar to the given query.
  Returns `{:ok, [KnowledgeItem.t()]}` or `{:error, reason}`.
  """
  def search(pid \\ __MODULE__, _query, query_embedding, opts \\ []) do
    GenServer.call(pid, {:search, query_embedding, opts})
  end

  @doc """
  Returns the configured chunk size for the knowledge manager.
  """
  def chunk_size(pid \\ __MODULE__) do
    GenServer.call(pid, :get_chunk_size)
  end

  @doc """
  Preprocesses text by removing markdown, code blocks, and normalizing whitespace.
  """
  def preprocess_text(text) do
    text
    |> remove_code_blocks()
    |> remove_markdown()
    |> remove_urls()
    |> normalize_whitespace()
  end

  @doc """
  Splits text into chunks while respecting sentence and paragraph boundaries.
  """
  def chunk_text(text, max_size \\ @default_chunk_size) do
    text
    # Split on paragraph boundaries first
    |> String.split(~r/\n\n+/)
    |> Enum.flat_map(fn paragraph ->
      paragraph
      # Split on sentence boundaries
      |> String.split(~r/(?<=\.)\s+/)
      |> Enum.reduce([], fn sentence, chunks ->
        case chunks do
          [] ->
            [sentence]

          [current | rest] ->
            potential = current <> " " <> sentence

            if String.length(potential) <= max_size do
              [potential | rest]
            else
              [sentence, current | rest]
            end
        end
      end)
      |> Enum.reverse()
    end)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    adapter = Keyword.get(opts, :adapter, DefaultAdapter)
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)

    case validate_adapter(adapter) do
      :ok ->
        case adapter.init(opts) do
          {:ok, adapter_state} ->
            {:ok,
             %{
               adapter: adapter,
               adapter_state: adapter_state,
               chunk_size: chunk_size
             }}

          {:error, reason} ->
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, {:invalid_adapter, reason}}
    end
  end

  @impl true
  def handle_call(
        {:create_knowledge, params},
        _from,
        %{adapter: adapter, adapter_state: state, chunk_size: chunk_size} = data
      ) do
    with {:ok, validated} <- validate_knowledge_params(params),
         processed_content = preprocess_text(validated.content),
         chunks = chunk_text(processed_content, chunk_size),
         items = create_knowledge_items(chunks, validated),
         {:ok, created} <- create_items(items, adapter, state) do
      result = if length(chunks) == 1, do: hd(created), else: created
      {:reply, {:ok, result}, data}
    else
      {:error, reason} -> {:reply, {:error, reason}, data}
    end
  end

  def handle_call(
        {:search, query_embedding, opts},
        _from,
        %{adapter: adapter, adapter_state: state} = data
      ) do
    result = adapter.search_knowledge_by_embedding(query_embedding, opts, state)
    {:reply, result, data}
  end

  def handle_call(:get_chunk_size, _from, %{chunk_size: size} = data) do
    {:reply, size, data}
  end

  # Private Helpers

  defp validate_adapter(adapter) do
    with {:module, _} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :init, 1),
         true <- function_exported?(adapter, :create_knowledge, 2),
         true <- function_exported?(adapter, :search_knowledge_by_embedding, 3) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :missing_callbacks}
    end
  end

  defp validate_knowledge_params(params) do
    required_keys = [:agent_id, :content]

    if Enum.all?(required_keys, &Map.has_key?(params, &1)) do
      validated =
        params
        |> Map.take(required_keys ++ [:metadata, :embedding])
        |> Map.new()

      {:ok, validated}
    else
      {:error, :invalid_params}
    end
  end

  defp create_knowledge_items(chunks, params) do
    Enum.map(chunks, fn chunk ->
      %KnowledgeItem{
        id: generate_id(),
        agent_id: params.agent_id,
        content: chunk,
        created_at: DateTime.utc_now(),
        metadata: Map.get(params, :metadata),
        embedding: Map.get(params, :embedding)
      }
    end)
  end

  defp create_items(items, adapter, state) do
    results = Enum.map(items, &adapter.create_knowledge(&1, state))

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, item} -> item end)}
    else
      {:error, :creation_failed}
    end
  end

  defp generate_id do
    "ki_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp remove_code_blocks(text) do
    String.replace(text, ~r/```[\s\S]*?```/, "")
  end

  defp remove_markdown(text) do
    text
    |> String.replace(~r/^#+ /, "")
    |> String.replace(~r/\*\*(.*?)\*\*/, "\\1")
    |> String.replace(~r/\*(.*?)\*/, "\\1")
    |> String.replace(~r/\[(.*?)\]\(.*?\)/, "\\1")
  end

  defp remove_urls(text) do
    text
    |> String.replace(~r/<(https?:\/\/[^>]+)>/, "\\1")
  end

  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
