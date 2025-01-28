defmodule Jido.Memory.KnowledgeTest do
  use ExUnit.Case, async: true
  alias Jido.Memory.{Knowledge, Types.KnowledgeItem}
  import Jido.Memory.TestHelpers

  setup do
    cleanup_ets_tables()
    name = :"test_#{:erlang.unique_integer()}"
    {:ok, pid} = Knowledge.start_link(adapter: Jido.Memory.MemoryAdapter.ETS, name: name)
    %{pid: pid}
  end

  describe "knowledge operations" do
    test "creates and retrieves knowledge items", %{pid: pid} do
      params = %{
        agent_id: "agent1",
        content: "The capital of France is Paris",
        metadata: %{
          source: "geography_facts",
          confidence: 0.95
        }
      }

      assert {:ok, %KnowledgeItem{} = item} = Knowledge.create_knowledge(pid, params)
      assert item.agent_id == params.agent_id
      assert item.content == params.content
      assert item.metadata == params.metadata
      assert item.id != nil
      assert item.created_at != nil
    end

    test "returns error for invalid knowledge params", %{pid: pid} do
      assert {:error, :invalid_params} = Knowledge.create_knowledge(pid, %{})
    end

    test "preprocesses content before storage", %{pid: pid} do
      params = %{
        agent_id: "agent1",
        content: """
        # Markdown Title
        Here's some **bold** text and a [link](https://example.com).
        ```elixir
        IO.puts("code block")
        ```
        """,
        metadata: %{source: "docs"}
      }

      {:ok, item} = Knowledge.create_knowledge(pid, params)
      assert item.content == "Markdown Title Here's some bold text and a link."
    end

    test "chunks large content into smaller pieces", %{pid: pid} do
      # Create a long text with multiple paragraphs
      content =
        Enum.map_join(1..5, "\n\n", fn i ->
          "This is paragraph #{i} with enough text to demonstrate the chunking functionality. " <>
            "It contains multiple sentences and should be split appropriately. " <>
            "Each chunk should maintain coherent meaning while staying within size limits."
        end)

      params = %{
        agent_id: "agent1",
        content: content,
        metadata: %{source: "test"}
      }

      {:ok, items} = Knowledge.create_knowledge(pid, params)
      assert length(items) > 1
      chunk_size = Knowledge.chunk_size(pid)

      assert Enum.all?(items, fn item ->
               String.length(item.content) <= chunk_size
             end)
    end

    test "searches knowledge by semantic similarity", %{pid: pid} do
      items = [
        {"The quick brown fox jumps over the lazy dog", [1.0, 0.0, 0.0]},
        {"A dog sleeps peacefully in the garden", [0.0, 1.0, 0.0]},
        {"The agile fox leaps across the sleeping hound", [0.9, 0.1, 0.0]}
      ]

      for {content, embedding} <- items do
        params = %{
          agent_id: "agent1",
          content: content,
          embedding: embedding,
          metadata: %{source: "test"}
        }

        {:ok, _} = Knowledge.create_knowledge(pid, params)
      end

      query = "fox jumping over dog"
      query_embedding = [1.0, 0.0, 0.0]

      {:ok, results} = Knowledge.search(pid, query, query_embedding)

      assert length(results) == 2
      [first, second] = results
      assert first.content == "The quick brown fox jumps over the lazy dog"
      assert second.content == "The agile fox leaps across the sleeping hound"
      assert first.similarity > second.similarity
    end

    test "handles concurrent operations", %{pid: pid} do
      # Create an initial item to ensure the table exists
      {:ok, _} =
        Knowledge.create_knowledge(pid, %{
          agent_id: "agent1",
          content: "Initial item",
          metadata: %{index: 0},
          embedding: [1.0, 0.0, 0.0]
        })

      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            # Create a simple embedding based on the index
            embedding = [
              :math.cos(i / 10),
              :math.sin(i / 10),
              0.0
            ]

            params = %{
              agent_id: "agent1",
              content: "Knowledge item #{i}",
              metadata: %{index: i},
              embedding: embedding
            }

            {:ok, item} = Knowledge.create_knowledge(pid, params)
            assert item.metadata.index == i
          end)
        end

      Enum.each(tasks, &Task.await/1)

      # Search with an embedding that should match items around index 10
      query_embedding = [
        :math.cos(1.0),
        :math.sin(1.0),
        0.0
      ]

      {:ok, results} = Knowledge.search(pid, "Knowledge", query_embedding, threshold: 0.5)
      assert length(results) > 0
      assert Enum.all?(results, &(&1.similarity >= 0.5))
    end
  end

  describe "text preprocessing" do
    test "removes markdown formatting" do
      text = "# Title\n**bold** and *italic*"
      assert Knowledge.preprocess_text(text) == "Title bold and italic"
    end

    test "removes code blocks" do
      text = """
      Here's some code:
      ```elixir
      def hello, do: "world"
      ```
      And more text.
      """

      assert Knowledge.preprocess_text(text) == "Here's some code: And more text."
    end

    test "removes URLs but keeps link text" do
      text = "Check [this link](https://example.com) and <https://direct.link>"
      assert Knowledge.preprocess_text(text) == "Check this link and https://direct.link"
    end

    test "normalizes whitespace" do
      text = "Multiple    spaces\nand\n\nnewlines"
      assert Knowledge.preprocess_text(text) == "Multiple spaces and newlines"
    end
  end

  describe "text chunking" do
    test "respects sentence boundaries" do
      text = "First sentence. Second sentence. Third sentence."
      chunks = Knowledge.chunk_text(text, 20)
      assert length(chunks) == 3
      assert Enum.all?(chunks, &String.ends_with?(&1, "."))
    end

    test "handles paragraphs" do
      text = "Paragraph one.\n\nParagraph two.\n\nParagraph three."
      chunks = Knowledge.chunk_text(text, 30)
      assert length(chunks) == 3
      assert Enum.all?(chunks, &(String.length(&1) <= 30))
    end

    test "preserves words" do
      text = "These are some words that should not be split in the middle."
      chunks = Knowledge.chunk_text(text, 20)

      assert Enum.all?(chunks, fn chunk ->
               String.split(chunk, " ") |> Enum.all?(&(String.length(&1) < 20))
             end)
    end
  end
end
