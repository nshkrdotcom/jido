defmodule JidoTest.Actions.FilesTest do
  use ExUnit.Case, async: true
  alias Jido.Actions.Files

  @moduletag :tmp_dir

  describe "WriteFile" do
    test "writes content to a file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test_write.txt")
      content = "Hello, World!"

      assert {:ok, result} = Files.WriteFile.run(%{path: path, content: content}, %{})
      assert result.path == path
      assert result.bytes_written == byte_size(content)
      assert File.read!(path) == content
    end

    test "returns error on write failure" do
      # Attempt to write to a non-existent directory
      path = "/non_existent_dir/test.txt"
      content = "This should fail"

      assert {:error, error_message} = Files.WriteFile.run(%{path: path, content: content}, %{})
      assert error_message =~ "Failed to write file"
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
