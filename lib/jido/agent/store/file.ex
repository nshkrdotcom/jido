defmodule Jido.Agent.Store.File do
  @moduledoc """
  File-based agent store adapter.

  Simple restart-safe storage that persists each agent to a separate file.
  Suitable for development and simple production use cases.

  ## Usage

      Jido.Agent.InstanceManager.child_spec(
        name: :sessions,
        agent: MyAgent,
        persistence: [
          store: {Jido.Agent.Store.File, path: "priv/agent_state"}
        ]
      )

  ## Options

  - `:path` - Directory path for state files (required). Created if it doesn't exist.

  ## File Format

  Files are named by hashing the key and stored as Erlang term format.
  """
  @behaviour Jido.Agent.Store

  @impl true
  def get(key, opts) do
    path = Keyword.fetch!(opts, :path)
    file_path = key_to_path(path, key)

    case File.read(file_path) do
      {:ok, binary} ->
        {:ok, :erlang.binary_to_term(binary, [:safe])}

      {:error, :enoent} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    ArgumentError -> {:error, :invalid_term}
  end

  @impl true
  def put(key, dump, opts) do
    path = Keyword.fetch!(opts, :path)
    ensure_dir(path)
    file_path = key_to_path(path, key)
    tmp_path = file_path <> ".tmp"
    binary = :erlang.term_to_binary(dump)

    # Atomic write: write to temp file, then rename
    with :ok <- File.write(tmp_path, binary),
         :ok <- File.rename(tmp_path, file_path) do
      :ok
    else
      {:error, reason} ->
        # Clean up temp file on failure
        File.rm(tmp_path)
        {:error, reason}
    end
  end

  @impl true
  def delete(key, opts) do
    path = Keyword.fetch!(opts, :path)
    file_path = key_to_path(path, key)

    case File.rm(file_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp key_to_path(base_path, key) do
    hash = :crypto.hash(:sha256, :erlang.term_to_binary(key)) |> Base.url_encode64(padding: false)
    Path.join(base_path, "#{hash}.agent")
  end

  defp ensure_dir(path) do
    File.mkdir_p!(path)
  end
end
