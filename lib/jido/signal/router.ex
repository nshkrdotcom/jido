defmodule Jido.Signal.Router do
  @moduledoc """
  A hybrid signal router combining trie-based path matching with pattern matching.
  """

  use ExDbug, enabled: true
  alias Jido.Signal

  @type handler :: (Signal.t() -> any())
  @type pattern_fn :: (Signal.t() -> boolean())
  @type matcher :: {pattern_fn, handler}
  @type priority :: integer()
  @type route_spec ::
          {String.t(), handler()}
          | {String.t(), pattern_fn(), handler()}
          | {String.t(), handler(), priority()}
          | {String.t(), pattern_fn(), handler(), priority()}

  @type trie_node :: %{
          optional(String.t()) => trie_node | node_handlers,
          optional(:*) => node_handlers,
          optional(:matchers) => [{pattern_fn, handler, priority}]
        }

  @type node_handlers :: %{
          optional(:handler) => {handler(), priority()},
          optional(:matchers) => [{pattern_fn, handler, priority}]
        }

  # Constants
  @valid_path_regex ~r/^[a-zA-Z0-9.*_-]+(\.[a-zA-Z0-9.*_-]+)*$/
  @default_priority 0

  defp validate_path(path) when is_binary(path) do
    if String.match?(path, @valid_path_regex) and not String.contains?(path, "..") do
      {:ok, path}
    else
      {:error, :invalid_path_format}
    end
  end

  defp validate_path(_), do: {:error, :invalid_path}

  defp validate_handler(handler) when is_function(handler, 1), do: {:ok, handler}
  defp validate_handler(_), do: {:error, :invalid_handler}

  defp validate_pattern_fn(pattern_fn) when is_function(pattern_fn, 1) do
    try do
      test_signal = %Signal{
        type: "",
        source: "",
        id: "",
        data: %{amount: 0, currency: "USD"}
      }

      case pattern_fn.(test_signal) do
        result when is_boolean(result) -> {:ok, pattern_fn}
        _ -> {:error, :invalid_pattern_function}
      end
    rescue
      _ -> {:error, :invalid_pattern_function}
    end
  end

  defp validate_pattern_fn(_), do: {:error, :invalid_pattern_function}

  defp validate_priority(priority) when is_integer(priority), do: {:ok, priority}
  defp validate_priority(_), do: {:error, :invalid_priority}

  defp sanitize_path(path) do
    path
    |> String.trim()
    |> String.replace(~r/\.+/, ".")
    |> String.replace(~r/(^\.|\.$)/, "")
  end

  defp emit_telemetry(event, metadata \\ %{}) do
    :telemetry.execute([:jido, :signal_router] ++ event, %{}, metadata)
  end

  @spec new([route_spec()]) :: trie_node()
  def new(routes \\ []) do
    dbug("Initializing router", routes: routes)
    Enum.reduce(routes, %{}, &add_route/2)
  end

  defp add_route({path, handler}, trie) when is_binary(path) and is_function(handler, 1) do
    dbug("Adding path route", path: path, handler: handler)

    case add_path_route(trie, path, handler) do
      {:error, _} -> trie
      new_trie -> new_trie
    end
  end

  defp add_route({path, handler, priority}, trie)
       when is_binary(path) and is_function(handler, 1) and is_integer(priority) do
    dbug("Adding path route", path: path, handler: handler, priority: priority)

    case add_path_route(trie, path, handler, priority) do
      {:error, _} -> trie
      new_trie -> new_trie
    end
  end

  defp add_route({path, pattern_fn, handler}, trie)
       when is_binary(path) and is_function(pattern_fn, 1) and is_function(handler, 1) do
    dbug("Adding pattern route", path: path, pattern_fn: pattern_fn, handler: handler)

    case add_pattern_route(trie, path, pattern_fn, handler) do
      {:error, _} -> trie
      new_trie -> new_trie
    end
  end

  defp add_route({path, pattern_fn, handler, priority}, trie)
       when is_binary(path) and is_function(pattern_fn, 1) and is_function(handler, 1) and
              is_integer(priority) do
    dbug("Adding pattern route",
      path: path,
      pattern_fn: pattern_fn,
      handler: handler,
      priority: priority
    )

    case add_pattern_route(trie, path, pattern_fn, handler, priority) do
      {:error, _} -> trie
      new_trie -> new_trie
    end
  end

  defp add_route(_invalid_route, trie) do
    dbug("Invalid route spec")
    emit_telemetry([:new, :error], %{reason: :invalid_route_spec})
    trie
  end

  def add_path_route(trie, path, handler, priority \\ @default_priority) do
    dbug("Adding path route", path: path, handler: handler, priority: priority)

    with {:ok, _} <- validate_path(path),
         {:ok, sanitized_path} <- {:ok, sanitize_path(path)},
         {:ok, validated_handler} <- validate_handler(handler),
         {:ok, validated_priority} <- validate_priority(priority),
         :ok <- check_route_collision(trie, sanitized_path) do
      emit_telemetry([:add_path_route], %{path: path})

      do_add_path_route(
        String.split(sanitized_path, "."),
        trie,
        {validated_handler, validated_priority}
      )
    else
      error ->
        dbug("Failed to add path route", error: error)
        emit_telemetry([:add_path_route, :error], %{reason: elem(error, 1)})
        error
    end
  end

  def add_pattern_route(trie, path, pattern_fn, handler, priority \\ @default_priority) do
    dbug("Adding pattern route",
      path: path,
      pattern_fn: pattern_fn,
      handler: handler,
      priority: priority
    )

    with {:ok, _} <- validate_path(path),
         {:ok, sanitized_path} <- {:ok, sanitize_path(path)},
         {:ok, validated_pattern} <- validate_pattern_fn(pattern_fn),
         {:ok, validated_handler} <- validate_handler(handler),
         {:ok, validated_priority} <- validate_priority(priority) do
      emit_telemetry([:add_pattern_route], %{path: path})

      do_add_pattern_route(
        String.split(sanitized_path, "."),
        trie,
        {validated_pattern, validated_handler, validated_priority}
      )
    else
      error ->
        dbug("Failed to add pattern route", error: error)
        emit_telemetry([:add_pattern_route, :error], %{reason: elem(error, 1)})
        error
    end
  end

  def remove_route(trie, path) do
    with {:ok, sanitized_path} <- validate_path(sanitize_path(path)) do
      segments = String.split(sanitized_path, ".")
      emit_telemetry([:remove_route], %{path: path})
      {:ok, do_remove_route(segments, trie)}
    end
  end

  def list_routes(trie) do
    emit_telemetry([:list_routes])
    do_list_routes(trie, [], "")
  end

  defp do_list_routes(trie, acc, prefix) do
    Enum.reduce(trie, acc, fn
      {"*", %{handler: handler}}, acc when is_tuple(handler) ->
        [{prefix <> "*", :path, elem(handler, 1)} | acc]

      {segment, %{handler: handler} = node}, acc when is_tuple(handler) ->
        new_prefix = prefix <> segment
        route = {new_prefix, :path, elem(handler, 1)}
        nested_routes = do_list_routes(Map.drop(node, [:handler]), acc, new_prefix <> ".")
        [route | nested_routes]

      {segment, %{matchers: matchers} = node}, acc ->
        new_prefix = prefix <> segment

        pattern_routes =
          Enum.map(matchers, fn {_, _, priority} -> {new_prefix, :pattern, priority} end)

        nested_routes = do_list_routes(Map.drop(node, [:matchers]), acc, new_prefix <> ".")
        pattern_routes ++ nested_routes

      {segment, node}, acc ->
        do_list_routes(node, acc, prefix <> segment <> ".")
    end)
  end

  # TODO: Check for collisions in pattern routes
  defp check_route_collision(trie, path) do
    segments = String.split(path, ".")

    case get_in(trie, segments) do
      %{handler: _} -> {:error, :route_already_exists}
      _ -> :ok
    end
  end

  defp do_remove_route([segment], trie) do
    Map.delete(trie, segment)
  end

  defp do_remove_route([segment | rest], trie) do
    case Map.get(trie, segment) do
      nil ->
        trie

      node ->
        updated_node = do_remove_route(rest, node)

        if map_size(updated_node) == 0 do
          Map.delete(trie, segment)
        else
          Map.put(trie, segment, updated_node)
        end
    end
  end

  defp do_add_path_route([segment], trie, {handler, priority}) do
    Map.update(trie, segment, %{handler: {handler, priority}}, fn node ->
      Map.put(node, :handler, {handler, priority})
    end)
  end

  defp do_add_path_route([segment | rest], trie, handler_info) do
    Map.update(trie, segment, do_add_path_route(rest, %{}, handler_info), fn node ->
      do_add_path_route(rest, node, handler_info)
    end)
  end

  defp do_add_pattern_route([segment], trie, {pattern_fn, handler, priority} = matcher) do
    Map.update(trie, segment, %{matchers: [matcher]}, fn node ->
      Map.update(node, :matchers, [matcher], &[matcher | &1])
    end)
  end

  defp do_add_pattern_route([segment | rest], trie, matcher) do
    Map.update(trie, segment, do_add_pattern_route(rest, %{}, matcher), fn node ->
      do_add_pattern_route(rest, node, matcher)
    end)
  end

  def route(trie, %Signal{type: type} = signal) do
    dbug("Routing signal", type: type)

    emit_telemetry([:route, :start], %{type: type})

    results =
      type
      |> String.split(".")
      |> do_route(trie, signal, [])
      |> sort_and_execute(signal)

    emit_telemetry([:route, :complete], %{type: type, results: results})

    if Enum.empty?(results), do: {:error, :no_handler}, else: {:ok, results}
  end

  defp do_route([], _trie, _signal, acc), do: acc

  defp do_route([segment | rest] = segments, trie, signal, acc) do
    dbug("Routing segments", segments: segments)

    matching_handlers =
      case Map.get(trie, segment) do
        nil ->
          acc

        node_handlers when rest == [] ->
          dbug("Found leaf node", segment: segment)
          collect_handlers(node_handlers, signal, acc)

        node when is_map(node) ->
          dbug("Found branch node", segment: segment)
          do_route(rest, node, signal, collect_handlers(node, signal, acc))
      end

    # Always try wildcard after specific matches
    try_wildcard(trie, signal, matching_handlers)
  end

  defp try_wildcard(trie, signal, acc) do
    dbug("Trying wildcard handler")

    case Map.get(trie, "*") do
      nil ->
        dbug("No wildcard handler found")
        acc

      node_handlers ->
        dbug("Found wildcard handler")
        collect_handlers(node_handlers, signal, acc)
    end
  end

  defp collect_handlers(%{handler: {handler, priority}} = node, signal, acc) do
    dbug("Collecting handlers with handler")

    pattern_matches = collect_pattern_matches(Map.get(node, :matchers, []), signal)
    [{handler, priority} | pattern_matches] ++ acc
  end

  defp collect_handlers(%{matchers: matchers}, signal, acc) do
    dbug("Collecting handlers with matchers")
    collect_pattern_matches(matchers, signal) ++ acc
  end

  defp collect_handlers(_, _signal, acc), do: acc

  defp collect_pattern_matches(matchers, signal) do
    dbug("Collecting pattern matches", count: length(matchers))

    Enum.reduce(matchers, [], fn {pattern_fn, handler, priority}, matches ->
      if pattern_fn.(signal), do: [{handler, priority} | matches], else: matches
    end)
  end

  defp sort_and_execute(handlers, signal) do
    handlers
    # Sort by priority descending
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.map(fn {handler, _priority} -> handler.(signal) end)
  end
end
