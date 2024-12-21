defmodule JidoTest.Actions.FilesTest do
  use ExUnit.Case, async: true
  alias Jido.Actions.Files

  @moduletag :tmp_dir

  describe "WriteFile" do
    test "writes content to a file with parent directory creation", %{tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "subdir", "test.txt"])
      content = "Hello, World!"

      assert {:ok, result} =
               Files.WriteFile.run(
                 %{path: path, content: content, create_dirs: true, mode: :write},
                 %{}
               )

      assert result.path == path
      assert result.bytes_written == byte_size(content)
      assert File.read!(path) == content
    end

    test "appends content to existing file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "append_test.txt")
      initial_content = "Initial"
      append_content = "Appended"

      File.write!(path, initial_content)

      assert {:ok, _} =
               Files.WriteFile.run(
                 %{path: path, content: append_content, create_dirs: false, mode: :append},
                 %{}
               )

      assert File.read!(path) == initial_content <> append_content
    end
  end

  describe "MakeDirectory" do
    test "creates a single directory", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "new_dir")

      assert {:ok, result} = Files.MakeDirectory.run(%{path: path, recursive: false}, %{})
      assert result.path == path
      assert File.dir?(path)
    end

    test "creates nested directories recursively", %{tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "parent", "child", "grandchild"])

      assert {:ok, result} = Files.MakeDirectory.run(%{path: path, recursive: true}, %{})
      assert result.path == path
      assert File.dir?(path)
    end

    test "fails when parent doesn't exist and recursive is false", %{tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "nonexistent", "child"])

      assert {:error, message} = Files.MakeDirectory.run(%{path: path, recursive: false}, %{})
      assert message =~ "Failed to create directory"
    end
  end

  describe "ListDirectory" do
    test "lists directory contents with pattern matching", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "test1.txt"), "")
      File.write!(Path.join(tmp_dir, "test2.txt"), "")
      File.write!(Path.join(tmp_dir, "other.log"), "")

      assert {:ok, result} =
               Files.ListDirectory.run(
                 %{path: tmp_dir, pattern: "*.txt", recursive: false},
                 %{}
               )

      assert length(result.entries) == 2
      assert Enum.all?(result.entries, &String.ends_with?(&1, ".txt"))
    end

    test "recursively lists directory contents", %{tmp_dir: tmp_dir} do
      subdir = Path.join(tmp_dir, "subdir")
      File.mkdir_p!(subdir)
      File.write!(Path.join(tmp_dir, "root.txt"), "")
      File.write!(Path.join(subdir, "sub.txt"), "")

      assert {:ok, result} = Files.ListDirectory.run(%{path: tmp_dir, recursive: true}, %{})
      assert "subdir" in result.entries
      assert "root.txt" in result.entries
    end
  end

  describe "DeleteFile" do
    test "deletes a single file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "to_delete.txt")
      File.write!(path, "delete me")

      assert {:ok, result} =
               Files.DeleteFile.run(%{path: path, recursive: false, force: false}, %{})

      assert result.path == path
      refute File.exists?(path)
    end

    test "recursively deletes directory and contents", %{tmp_dir: tmp_dir} do
      dir_path = Path.join(tmp_dir, "to_delete")
      File.mkdir_p!(Path.join(dir_path, "subdir"))
      File.write!(Path.join(dir_path, "file1.txt"), "")
      File.write!(Path.join(Path.join(dir_path, "subdir"), "file2.txt"), "")

      assert {:ok, result} = Files.DeleteFile.run(%{path: dir_path, recursive: true}, %{})
      assert is_list(result.deleted)
      refute File.exists?(dir_path)
    end

    test "handles read-only files with force option", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "readonly.txt")
      File.write!(path, "protected")
      File.chmod!(path, 0o444)

      assert {:ok, _} = Files.DeleteFile.run(%{path: path, recursive: false, force: true}, %{})
      refute File.exists?(path)
    end
  end

  describe "ReadFile" do
    test "reads content from a file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test_read.txt")
      content = "Hello, World!"
      File.write!(path, content)

      assert {:ok, result} = Files.ReadFile.run(%{path: path}, %{})
      assert result.path == path
      assert result.content == content
    end

    test "returns error when file doesn't exist" do
      path = "/non_existent_file.txt"

      assert {:error, error_message} = Files.ReadFile.run(%{path: path}, %{})
      assert error_message =~ "Failed to read file"
    end
  end

  describe "CopyFile" do
    test "copies a file from source to destination", %{tmp_dir: tmp_dir} do
      source = Path.join(tmp_dir, "source.txt")
      destination = Path.join(tmp_dir, "destination.txt")
      content = "Copy me!"
      File.write!(source, content)

      assert {:ok, result} = Files.CopyFile.run(%{source: source, destination: destination}, %{})
      assert result.source == source
      assert result.destination == destination
      assert result.bytes_copied == byte_size(content)
      assert File.read!(destination) == content
    end

    test "returns error when source file doesn't exist" do
      source = "/non_existent_source.txt"
      destination = "/some_destination.txt"

      assert {:error, error_message} =
               Files.CopyFile.run(%{source: source, destination: destination}, %{})

      assert error_message =~ "Failed to copy file"
    end
  end

  describe "MoveFile" do
    test "moves a file from source to destination", %{tmp_dir: tmp_dir} do
      source = Path.join(tmp_dir, "source_move.txt")
      destination = Path.join(tmp_dir, "destination_move.txt")
      content = "Move me!"
      File.write!(source, content)

      assert {:ok, result} = Files.MoveFile.run(%{source: source, destination: destination}, %{})
      assert result.source == source
      assert result.destination == destination
      assert File.read!(destination) == content
      refute File.exists?(source)
    end

    test "returns error when source file doesn't exist" do
      source = "/non_existent_source.txt"
      destination = "/some_destination.txt"

      assert {:error, error_message} =
               Files.MoveFile.run(%{source: source, destination: destination}, %{})

      assert error_message =~ "Failed to move file"
    end
  end
end
