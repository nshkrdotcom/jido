defmodule Jido.Memory.RAGKnowledgeTest do
  use JidoTest.Case, async: true
  alias Jido.Memory.RAGKnowledge
  import Jido.Memory.TestHelpers

  setup do
    cleanup_ets_tables()
    name = :"test_#{:erlang.unique_integer()}"
    {:ok, pid} = RAGKnowledge.start_link(adapter: Jido.Memory.MemoryAdapter.ETS, name: name)
    %{pid: pid}
  end

  describe "document ingestion" do
    @tag :skip
    test "ingests markdown documents with metadata", %{pid: pid} do
      content = """
      # Introduction to Elixir

      Elixir is a dynamic, functional language designed for building scalable applications.

      ## Key Features

      1. **Functional Programming**: Pure functions and immutable data.
      2. **Scalability**: Built on the Erlang VM (BEAM).
      3. **Fault Tolerance**: Supervisor trees and isolation.

      ## Code Example

      ```elixir
      defmodule Hello do
        def world, do: "Hello, World!"
      end
      ```

      For more information, visit [elixir-lang.org](https://elixir-lang.org).
      """

      metadata = %{
        source: "elixir_docs",
        category: "programming",
        tags: ["elixir", "functional", "beam"]
      }

      {:ok, items} = RAGKnowledge.ingest_document(pid, content, metadata)

      assert length(items) > 1

      assert Enum.all?(items, fn item ->
               item.metadata.source == "elixir_docs" &&
                 item.metadata.category == "programming" &&
                 item.metadata.tags == ["elixir", "functional", "beam"] &&
                 item.metadata.section != nil
             end)
    end

    @tag :skip
    test "extracts and preserves document structure", %{pid: pid} do
      content = """
      # Main Title

      Introduction paragraph.

      ## Section 1

      First section content.

      ## Section 2

      Second section content.

      ### Subsection 2.1

      Subsection content.
      """

      {:ok, items} = RAGKnowledge.ingest_document(pid, content)

      sections = Enum.map(items, & &1.metadata.section)
      assert Enum.any?(sections, &(&1 == "introduction"))
      assert Enum.any?(sections, &(&1 == "section_1"))
      assert Enum.any?(sections, &(&1 == "section_2"))
      assert Enum.any?(sections, &(&1 == "section_2.subsection_21"))
    end

    @tag :skip
    test "handles code blocks appropriately", %{pid: pid} do
      content = """
      # Code Examples

      Here's a simple function:

      ```elixir
      def add(a, b), do: a + b
      ```

      And another one:

      ```python
      def multiply(a, b):
          return a * b
      ```
      """

      {:ok, items} = RAGKnowledge.ingest_document(pid, content)

      code_items = Enum.filter(items, &(&1.metadata.type == "code"))
      text_items = Enum.filter(items, &(&1.metadata.type == "text"))

      assert length(code_items) == 2
      assert Enum.any?(code_items, &(&1.metadata.language == "elixir"))
      assert Enum.any?(code_items, &(&1.metadata.language == "python"))
      assert length(text_items) > 0
    end
  end

  describe "contextual search" do
    @tag :skip
    test "retrieves items with context", %{pid: pid} do
      # First ingest some documents
      docs = [
        {"# Processes",
         """
         Elixir processes are lightweight and isolated.
         They communicate through message passing.

         ## Message Passing
         Messages can be sent with the `send` function.
         """},
        {"# GenServer",
         """
         GenServer is a behaviour module for implementing server processes.

         ## Callbacks
         The main callbacks are `init/1` and `handle_call/3`.
         """}
      ]

      for {title, content} <- docs do
        {:ok, _} = RAGKnowledge.ingest_document(pid, content, %{title: title})
      end

      query = "How do processes communicate?"
      # Simulated embedding
      query_embedding = [1.0, 0.0, 0.0]

      {:ok, results} = RAGKnowledge.search_with_context(pid, query, query_embedding)

      assert length(results) > 0
      first_result = hd(results)

      # Should include the matching section and its context
      assert first_result.content =~ "message passing"
      assert first_result.context != nil
      assert first_result.context.title == "Processes"
      assert first_result.context.section != nil
    end

    @tag :skip
    test "handles hierarchical context", %{pid: pid} do
      content = """
      # Data Types

      ## Collections

      ### Lists
      Lists are linked data structures.

      ### Maps
      Maps are key-value stores.

      ## Numbers

      ### Integers
      Integers have arbitrary precision.

      ### Floats
      Floats are 64-bit double precision.
      """

      {:ok, _} = RAGKnowledge.ingest_document(pid, content)

      query = "How are maps implemented?"
      # Simulated embedding
      query_embedding = [1.0, 0.0, 0.0]

      {:ok, [result | _]} = RAGKnowledge.search_with_context(pid, query, query_embedding)

      assert result.context.hierarchy == ["Data Types", "Collections", "Maps"]
      assert result.context.siblings == ["Lists"]
      assert result.context.parent == "Collections"
    end
  end

  describe "knowledge graph" do
    @tag :skip
    test "builds relationships between sections", %{pid: pid} do
      content = """
      # Supervisor

      Supervisors manage other processes.

      ## Child Specification

      Child specs define process startup.

      ## Strategies

      ### One For One

      Restarts only failed children.

      ### One For All

      Restarts all children.
      """

      {:ok, _} = RAGKnowledge.ingest_document(pid, content)

      {:ok, graph} = RAGKnowledge.get_document_graph(pid, "Supervisor")

      assert graph.nodes["supervisor"]
      assert graph.nodes["child_specification"]
      assert graph.nodes["strategies"]
      assert graph.nodes["one_for_one"]
      assert graph.nodes["one_for_all"]

      # Verify relationships
      assert Enum.any?(graph.edges, fn edge ->
               edge.from == "supervisor" && edge.to == "child_specification" &&
                 edge.type == :contains
             end)

      assert Enum.any?(graph.edges, fn edge ->
               edge.from == "strategies" && edge.to == "one_for_one" &&
                 edge.type == :contains
             end)
    end

    @tag :skip
    test "tracks references between documents", %{pid: pid} do
      docs = [
        {"processes.md",
         """
         # Processes
         See [GenServer](#genserver) for server processes.
         """},
        {"genserver.md",
         """
         # GenServer
         Implements the [process](#processes) server pattern.
         """}
      ]

      for {file, content} <- docs do
        {:ok, _} = RAGKnowledge.ingest_document(pid, content, %{file: file})
      end

      {:ok, references} = RAGKnowledge.get_document_references(pid, "processes.md")

      assert Enum.any?(references.outgoing, fn ref ->
               ref.target == "genserver.md" && ref.type == :link
             end)

      {:ok, back_references} = RAGKnowledge.get_document_references(pid, "genserver.md")

      assert Enum.any?(back_references.incoming, fn ref ->
               ref.source == "processes.md" && ref.type == :link
             end)
    end
  end
end
