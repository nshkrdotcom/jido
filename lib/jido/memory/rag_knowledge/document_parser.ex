defmodule Jido.Memory.RAGKnowledge.DocumentParser do
  @moduledoc """
  Handles parsing of markdown documents into sections.
  """

  @doc """
  Parses a markdown document into sections.
  Each section contains:
  - title: The section title
  - level: The header level (1-6)
  - content: The section content
  - code_blocks: List of code blocks in the section
  - type: "text" or "code"
  - section: Normalized section identifier
  """
  def parse_markdown(content) do
    # First, extract any content before the first header
    {intro_content, rest_content} = split_introduction(content)

    # Parse the rest of the content
    lines = String.split(rest_content, "\n")

    {sections, current_section, _in_code_block, _code_content} =
      Enum.reduce(lines, {[], nil, false, ""}, &process_line/2)

    # Add the last section if it exists
    sections =
      if current_section do
        [current_section | sections]
      else
        sections
      end

    sections = Enum.reverse(sections)

    # Add introduction section if there was content before the first header
    sections =
      if String.trim(intro_content) != "" do
        [
          %{
            level: 1,
            title: "Introduction",
            content: intro_content,
            code_blocks: [],
            type: "text",
            language: nil,
            section: "introduction"
          }
          | sections
        ]
      else
        # If there's no explicit introduction content but the first section has content before its header,
        # convert that section into an introduction section
        case sections do
          [%{level: 1, content: content} = first | rest] when content != "" ->
            [%{first | title: "Introduction", section: "introduction"} | rest]

          _ ->
            sections
        end
      end

    # Process each section to extract code blocks and clean up content
    Enum.flat_map(sections, fn section ->
      case section.type do
        "text" ->
          {text_content, code_blocks} = extract_code_blocks(section.content)

          text_section = %{
            section
            | content: String.trim(text_content),
              code_blocks: [],
              section:
                if(section.title == "Introduction",
                  do: "introduction",
                  else: normalize_section_name(section.title)
                )
          }

          code_sections =
            Enum.map(code_blocks, fn {code, lang} ->
              %{
                level: section.level + 1,
                title: "Code Block",
                content: code,
                code_blocks: [],
                type: "code",
                language: lang,
                parent: section.title,
                section: "#{normalize_section_name(section.title)}_code"
              }
            end)

          [text_section | code_sections]

        "code" ->
          [section]
      end
    end)
  end

  defp split_introduction(content) do
    case Regex.run(~r/\A(.*?)(?=^#\s)/ms, content) do
      [_, intro] -> {String.trim(intro), String.replace_prefix(content, intro, "")}
      nil -> {"", content}
    end
  end

  defp process_line(line, {sections, current_section, _in_code_block, _code_content}) do
    cond do
      # New section header
      String.match?(line, ~r/^#+\s/) ->
        {level, title} = parse_header(line)
        new_sections = if current_section, do: [current_section | sections], else: sections

        # Build hierarchical section name
        parent_section =
          case sections do
            [%{level: parent_level, section: parent_section} | _] when parent_level < level ->
              parent_section

            _ ->
              nil
          end

        section_name =
          if parent_section do
            case String.match?(title, ~r/\d+\.\d+/) do
              true ->
                [parent_num, sub_num] =
                  Regex.run(~r/(\d+)\.(\d+)/, title)
                  |> Enum.drop(1)

                "#{parent_section}.subsection_#{parent_num}#{sub_num}"

              false ->
                normalized_title = normalize_section_name(title)

                case String.match?(normalized_title, ~r/^section_\d+$/) do
                  true -> normalized_title
                  false -> "#{parent_section}.#{normalized_title}"
                end
            end
          else
            normalize_section_name(title)
          end

        {new_sections,
         %{
           level: level,
           title: title,
           content: "",
           code_blocks: [],
           type: "text",
           language: nil,
           section: section_name
         }, false, ""}

      # Regular content
      true ->
        if current_section do
          {sections, %{current_section | content: current_section.content <> line <> "\n"}, false,
           ""}
        else
          # Create an introduction section for content before any header
          intro_section = %{
            level: 1,
            title: "Introduction",
            content: line <> "\n",
            code_blocks: [],
            type: "text",
            language: nil,
            section: "introduction"
          }

          {sections, intro_section, false, ""}
        end
    end
  end

  defp parse_header(line) do
    [hashes | words] = String.split(line, " ", trim: true)
    level = String.length(hashes)
    title = Enum.join(words, " ")
    {level, title}
  end

  defp extract_code_blocks(content) do
    {blocks, remaining_content} =
      Regex.scan(~r/```(\w+)?\n(.*?)```/s, content)
      |> Enum.reduce({[], content}, fn
        [full_match, lang, code], {blocks, content} ->
          {[{String.trim(code), lang} | blocks], String.replace(content, full_match, "")}
      end)

    {String.trim(remaining_content), Enum.reverse(blocks)}
  end

  defp normalize_section_name(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s\d.-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.replace(~r/subsection\s*(\d+)\.(\d+)/, "subsection_\\1\\2")
    |> String.replace(~r/(\d+)\.(\d+)/, "subsection_\\1\\2")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  # defp clean_content(content) do
  #   content
  #   # Remove code blocks
  #   |> String.replace(~r/```.*?```/s, "")
  #   # Replace links with text
  #   |> String.replace(~r/\[([^\]]+)\]\([^\)]+\)/, "\\1")
  #   |> String.replace(~r/\s+/, " ")
  #   |> String.trim()
  # end
end
