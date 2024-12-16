defmodule Jido.Actions.Files do
  @moduledoc """
  Actions for file workflows
  """
  alias Jido.Action

  defmodule WriteFile do
    @moduledoc "Writes content to a file"
    use Action,
      name: "write_file",
      description: "Writes content to a file",
      schema: [
        path: [type: :string, required: true],
        content: [type: :string, required: true]
      ]

    @impl true
    def run(%{path: path, content: content}, _context) do
      case File.write(path, content) do
        :ok -> {:ok, %{path: path, bytes_written: byte_size(content)}}
        {:error, reason} -> {:error, "Failed to write file: #{inspect(reason)}"}
      end
    end
  end

  defmodule ReadFile do
    @moduledoc "Reads content from a file"
    use Action,
      name: "read_file",
      description: "Reads content from a file",
      schema: [
        path: [type: :string, required: true]
      ]

    @impl true
    def run(%{path: path}, _context) do
      case File.read(path) do
        {:ok, content} -> {:ok, %{path: path, content: content}}
        {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
      end
    end
  end

  defmodule CopyFile do
    @moduledoc "Copies a file from source to destination"
    use Action,
      name: "CopyFile",
      description: "Copies a file from source to destination",
      schema: [
        source: [type: :string, required: true, doc: "Path to the source file"],
        destination: [type: :string, required: true, doc: "Path to the destination file"]
      ]

    @impl true
    def run(%{source: source, destination: destination}, _context) do
      case File.copy(source, destination) do
        {:ok, bytes_copied} ->
          {:ok, %{source: source, destination: destination, bytes_copied: bytes_copied}}

        {:error, reason} ->
          {:error, "Failed to copy file: #{inspect(reason)}"}
      end
    end
  end

  defmodule MoveFile do
    @moduledoc "Moves a file from source to destination"
    use Action,
      name: "move_file",
      description: "Moves a file from source to destination",
      schema: [
        source: [type: :string, required: true],
        destination: [type: :string, required: true]
      ]

    @impl true
    def run(%{source: source, destination: destination}, _context) do
      case File.rename(source, destination) do
        :ok -> {:ok, %{source: source, destination: destination}}
        {:error, reason} -> {:error, "Failed to move file: #{inspect(reason)}"}
      end
    end
  end
end
