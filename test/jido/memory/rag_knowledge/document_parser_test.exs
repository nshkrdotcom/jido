defmodule Jido.Memory.RAGKnowledge.DocumentParserTest do
  use JidoTest.Case, async: true
  alias Jido.Memory.RAGKnowledge.DocumentParser

  describe "parse_markdown/1" do
    test "parses sections with different header levels" do
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

      sections = DocumentParser.parse_markdown(content)

      # We expect 4 sections:
      # 1. Introduction (from content before first header)
      # 2. Section 1
      # 3. Section 2
      # 4. Subsection 2.1
      assert length(sections) == 4
      assert Enum.any?(sections, &(&1.title == "Introduction"))
      assert Enum.any?(sections, &(&1.title == "Section 1"))
      assert Enum.any?(sections, &(&1.title == "Section 2"))
      assert Enum.any?(sections, &(&1.title == "Subsection 2.1"))

      # Verify levels
      section_1 = Enum.find(sections, &(&1.title == "Section 1"))
      subsection = Enum.find(sections, &(&1.title == "Subsection 2.1"))

      assert section_1.level == 2
      assert subsection.level == 3
    end

    test "handles code blocks" do
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

      sections = DocumentParser.parse_markdown(content)

      code_sections = Enum.filter(sections, &(&1.type == "code"))
      text_sections = Enum.filter(sections, &(&1.type == "text"))

      assert length(code_sections) == 2
      assert Enum.any?(code_sections, &(&1.language == "elixir"))
      assert Enum.any?(code_sections, &(&1.language == "python"))
      assert length(text_sections) == 1
    end

    test "creates introduction section for content before first header" do
      content = """
      This is some introductory text.
      It should be in its own section.

      # First Header

      Some content.
      """

      sections = DocumentParser.parse_markdown(content)

      intro = Enum.find(sections, &(&1.title == "Introduction"))
      assert intro
      assert intro.level == 1

      assert String.trim(intro.content) ==
               "This is some introductory text.\nIt should be in its own section."

      assert intro.section == "introduction"
    end
  end
end
