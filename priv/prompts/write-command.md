dddd
# Writing Command Modules for Jido

A Jido Command Module is a reusable collection of related commands that orchestrate sequences of actions. Each command has a unique name, descriptive documentation, and a schema defining its parameters.

## Command Module Structure

Create a command module by:

1. Using the `Jido.Command` behavior
2. Implementing `commands/0` to define available commands
3. Implementing `handle_command/3` to sequence actions

Basic template:

```elixir
defmodule MyApp.MyCommand do
  use Jido.Command
  
  @impl true
  def commands do
    [
      my_command: [
        description: "Does something specific",
        schema: [
          param1: [type: :string, required: true, doc: "First parameter"],
          param2: [type: :integer, default: 42, doc: "Optional second parameter"] 
        ]
      ]
    ]
  end

  @impl true
  def handle_command(:my_command, agent, %{param1: p1, param2: p2}) do
    actions = [
      {MyAction1, [value: p1]},
      {MyAction2, [value: p2]}
    ]
    {:ok, actions}
  end
end
```

## Best Practices

1. Group Related Commands
   - Each command module should contain thematically related commands
   - Example: GroupMovementCommand for move, patrol, navigate commands

2. Clear Command Names
   - Use descriptive verb-noun combinations
   - Examples: generate_text, analyze_image, fetch_data

3. Thorough Documentation
   - Document each command's purpose
   - Explain parameter requirements
   - Provide usage examples

4. Robust Parameter Schemas
   - Use NimbleOptions schemas to validate inputs
   - Include parameter descriptions
   - Set appropriate defaults
   - Handle required vs optional params

5. Action Sequencing
   - Return ordered lists of actions
   - Consider dependencies between actions
   - Handle error cases
   - Use pattern matching for command variants

## Example Command Module

Here's a complete example of a well-structured command module:

```elixir
defmodule MyApp.DocumentCommand do
  @moduledoc """
  Commands for document processing and analysis.
  """
  use Jido.Command
  
  alias MyApp.Actions.{
    ParseDocument,
    ExtractText,
    AnalyzeContent,
    GenerateSummary
  }

  @impl true
  def commands do
    [
      analyze_document: [
        description: "Analyzes a document and generates insights",
        schema: [
          document_path: [
            type: :string,
            required: true,
            doc: "Path to document file"
          ],
          output_format: [
            type: {:in, [:text, :json, :html]},
            default: :text,
            doc: "Desired output format"
          ],
          include_summary: [
            type: :boolean,
            default: true,
            doc: "Whether to include summary"
          ]
        ]
      ],
      
      extract_text: [
        description: "Extracts plain text from document",
        schema: [
          document_path: [
            type: :string,
            required: true,
            doc: "Path to document file"
          ]
        ]
      ]
    ]
  end

  @impl true
  def handle_command(:analyze_document, _agent, params) do
    actions = [
      {ParseDocument, [path: params.document_path]},
      {ExtractText, []},
      {AnalyzeContent, [format: params.output_format]}
    ]

    actions = if params.include_summary do
      actions ++ [{GenerateSummary, []}]
    else
      actions
    end

    {:ok, actions}
  end

  def handle_command(:extract_text, _agent, %{document_path: path}) do
    {:ok, [
      {ParseDocument, [path: path]},
      {ExtractText, []}
    ]}
  end
end
```

## Testing Command Modules

Test your command modules thoroughly:

```elixir
defmodule MyApp.DocumentCommandTest do
  use ExUnit.Case, async: true
  
  alias MyApp.DocumentCommand
  
  describe "commands/0" do
    test "defines expected commands" do
      commands = DocumentCommand.commands()
      assert Keyword.has_key?(commands, :analyze_document)
      assert Keyword.has_key?(commands, :extract_text)
    end
    
    test "commands have required fields" do
      commands = DocumentCommand.commands()
      
      Enum.each(commands, fn {name, spec} ->
        assert is_atom(name)
        assert is_binary(spec[:description])
        assert is_list(spec[:schema])
      end)
    end
  end
  
  describe "handle_command/3" do
    test "analyze_document returns correct action sequence" do
      params = %{
        document_path: "test.pdf",
        output_format: :json,
        include_summary: true
      }
      
      assert {:ok, actions} = 
        DocumentCommand.handle_command(:analyze_document, nil, params)
        
      assert length(actions) == 4
      assert {ParseDocument, _} = List.first(actions)
      assert {GenerateSummary, _} = List.last(actions)
    end
    
    test "extracts text without summary when specified" do
      params = %{
        document_path: "test.pdf",
        output_format: :text,
        include_summary: false
      }
      
      assert {:ok, actions} = 
        DocumentCommand.handle_command(:analyze_document, nil, params)
        
      assert length(actions) == 3
      refute Enum.any?(actions, fn {action, _} -> 
        action == GenerateSummary
      end)
    end
  end
end
```

## Command Registration

Register commands with the Command Manager:

```elixir
{:ok, manager} = Manager.new()
|> Manager.register(MyApp.DocumentCommand)

# Use in agent
{:ok, agent} = Agent.new()
|> Agent.set_command_manager(manager)

# Execute command
{:ok, actions} = Manager.dispatch(manager, :analyze_document, agent, %{
  document_path: "doc.pdf",
  output_format: :json
})
```