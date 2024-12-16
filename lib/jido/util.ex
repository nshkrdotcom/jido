defmodule Jido.Util do
  @moduledoc """
  A collection of utility functions for the Jido framework.

  This module provides various helper functions that are used throughout the Jido framework,
  including:

  - ID generation
  - Name validation
  - Error handling
  - Logging utilities

  These utilities are designed to support common operations and maintain consistency
  across the Jido ecosystem. They encapsulate frequently used patterns and provide
  a centralized location for shared functionality.

  Many of the functions in this module are used internally by other Jido modules,
  but they can also be useful for developers building applications with Jido.
  """

  alias Jido.Error

  require OK
  require Logger

  @name_regex ~r/^[a-zA-Z][a-zA-Z0-9_]*$/

  @doc """
  Generates a unique ID.
  """
  @spec generate_id() :: String.t()
  def generate_id, do: UUID.uuid4()

  @doc """
  Validates the name of a Action.

  The name must contain only letters, numbers, and underscores.

  ## Parameters

  - `name`: The name to validate.

  ## Returns

  - `{:ok, name}` if the name is valid.
  - `{:error, reason}` if the name is invalid.

  ## Examples

      iex> Jido.Action.validate_name("valid_name_123")
      {:ok, "valid_name_123"}

      iex> Jido.Action.validate_name("invalid-name")
      {:error, %Jido.Error{type: :validation_error, message: "The name must contain only letters, numbers, and underscores."}}

  """
  @spec validate_name(any()) :: {:ok, String.t()} | {:error, Error.t()}
  def validate_name(name) when is_binary(name) do
    if Regex.match?(@name_regex, name) do
      OK.success(name)
    else
      "The name must start with a letter and contain only letters, numbers, and underscores."
      |> Error.validation_error()
      |> OK.failure()
    end
  end

  def validate_name(_) do
    "Invalid name format."
    |> Error.validation_error()
    |> OK.failure()
  end

  def validate_planner(planner) when is_atom(planner) do
    if function_exported?(planner, :plan, 3) do
      {:ok, planner}
    else
      {:error, "Planner module must implement the Jido.Planner behavior with a plan/3 function."}
    end
  end

  def validate_planner(_) do
    {:error, "Invalid planner format. Expected an atom representing a module."}
  end

  defmacro __using__(opts \\ []) do
    quote do
      import Jido.Util
      require Jido.Util

      @debug_opts unquote(opts)
      @debug_enabled Keyword.get(unquote(opts), :debug_enabled, true)
    end
  end

  defmacro debug(message, metadata \\ []) do
    quote do
      if @debug_enabled do
        caller = "#{__MODULE__}.#{elem(__ENV__.function, 0)}"
        prefixed_message = "[#{caller}] #{unquote(message)}"
        Jido.Util.log(:debug, prefixed_message, unquote(metadata), @debug_opts)
      end
    end
  end

  defmacro error(message, metadata \\ []) do
    quote do
      if @debug_enabled do
        caller = "#{__MODULE__}.#{elem(__ENV__.function, 0)}"
        prefixed_message = "[#{caller}] #{unquote(message)}"
        Jido.Util.log(:error, prefixed_message, unquote(metadata), @debug_opts)
      end
    end
  end

  def log(level, message, metadata, opts) do
    if should_log?(level, opts) do
      formatted_metadata = format_metadata(metadata, opts)
      log_message = "#{message} #{formatted_metadata}"

      case level do
        :debug -> Logger.debug(log_message)
        :error -> Logger.error(log_message)
      end
    end
  end

  defp should_log?(level, opts) do
    config = Application.get_env(:jido, Jido.Util, [])
    env = Application.get_env(:jido, :env, :prod)

    debug_levels = opts[:levels] || config[:levels] || [:debug, :error]
    env_whitelist = opts[:env] || config[:env] || [:dev, :test]
    debug_enabled = opts[:debug_enabled] || false

    level in debug_levels and (env in env_whitelist or debug_enabled)
  end

  defp format_metadata(metadata, opts) do
    max_length = opts[:max_length] || 500
    truncate_threshold = opts[:truncate_threshold] || 100

    Enum.map_join(metadata, ", ", fn {key, value} ->
      formatted_value = format_value(value, max_length, truncate_threshold)
      "#{key}: #{formatted_value}"
    end)
  end

  defp format_value(value, max_length, truncate_threshold) do
    formatted = inspect(value, limit: :infinity, pretty: false)

    if String.length(formatted) > truncate_threshold do
      truncated = String.slice(formatted, 0, max_length)
      "#{truncated}... (truncated)"
    else
      formatted
    end
  end
end
