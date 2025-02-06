defmodule Jido.Signal do
  @moduledoc """
  Defines the structure and behavior of a Signal in the Jido system.
  Implements CloudEvents specification v1.0.2 with Jido-specific extensions.
  """

  alias Jido.Instruction
  alias Jido.Signal.Dispatch
  use TypedStruct

  typedstruct do
    field(:specversion, String.t(), default: "1.0.2")
    field(:id, String.t(), enforce: true, default: UUID.uuid4())
    field(:source, String.t(), enforce: true)
    field(:type, String.t(), enforce: true)
    field(:subject, String.t())
    field(:time, String.t())
    field(:datacontenttype, String.t())
    field(:dataschema, String.t())
    field(:data, term())
    # Jido-specific fields
    field(:jido_instructions, Jido.Runner.Instruction.instruction_list())
    field(:jido_opts, map())
    field(:jido_causation_id, String.t())
    field(:jido_correlation_id, String.t())
    field(:jido_dispatch, Dispatch.t())
    field(:jido_metadata, map())
  end

  @doc """
  Creates a new Signal struct, raising an error if invalid.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `Signal.t()` if the attributes are valid.

  ## Raises

  `RuntimeError` if the attributes are invalid.

  ## Examples

      iex> Jido.Signal.new!(%{type: "example.event", source: "/example"})
      %Jido.Signal{type: "example.event", source: "/example", ...}

      iex> Jido.Signal.new!(type: "example.event", source: "/example")
      %Jido.Signal{type: "example.event", source: "/example", ...}

  """
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Creates a new Signal struct.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the attributes are valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.new(%{type: "example.event", source: "/example", id: "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

      iex> Jido.Signal.new(type: "example.event", source: "/example")
      {:ok, %Jido.Signal{type: "example.event", source: "/example", ...}}

  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  def new(attrs) when is_map(attrs) do
    caller =
      Process.info(self(), :current_stacktrace)
      |> elem(1)
      |> Enum.find(fn {mod, _fun, _arity, _info} ->
        mod_str = to_string(mod)
        mod_str != "Elixir.Jido.Signal" and mod_str != "Elixir.Process"
      end)
      |> elem(0)
      |> to_string()

    defaults = %{
      "specversion" => "1.0.2",
      "id" => UUID.uuid4(),
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => caller
    }

    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.merge(defaults, fn _k, user_val, _default_val -> user_val end)
    |> from_map()
  end

  @doc """
  Creates a new Signal struct from a map.

  ## Parameters

  - `map`: A map containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the map is valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.from_map(%{"type" => "example.event", "source" => "/example", "id" => "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with :ok <- parse_specversion(map),
         {:ok, type} <- parse_type(map),
         {:ok, source} <- parse_source(map),
         {:ok, id} <- parse_id(map),
         {:ok, subject} <- parse_subject(map),
         {:ok, time} <- parse_time(map),
         {:ok, datacontenttype} <- parse_datacontenttype(map),
         {:ok, dataschema} <- parse_dataschema(map),
         {:ok, data} <- parse_data(map["data"]),
         {:ok, jido_instructions} <- parse_jido_instructions(map["jido_instructions"]),
         {:ok, jido_opts} <- parse_jido_opts(map["jido_opts"]),
         {:ok, jido_correlation_id} <- parse_correlation_id(map["jido_correlation_id"]),
         {:ok, jido_causation_id} <- parse_causation_id(map["jido_causation_id"]),
         {:ok, jido_dispatch} <- parse_jido_dispatch(map["jido_dispatch"]) do
      event = %__MODULE__{
        specversion: "1.0.2",
        type: type,
        source: source,
        id: id,
        subject: subject,
        time: time,
        datacontenttype: datacontenttype || if(data, do: "application/json"),
        dataschema: dataschema,
        data: data,
        jido_instructions: jido_instructions,
        jido_opts: jido_opts,
        jido_correlation_id: jido_correlation_id,
        jido_causation_id: jido_causation_id,
        jido_dispatch: jido_dispatch
      }

      {:ok, event}
    else
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  def map_to_signal_data(signals, fields \\ [])

  @spec map_to_signal_data(list(struct), Keyword.t()) :: list(t())
  def map_to_signal_data(signals, fields) when is_list(signals) do
    Enum.map(signals, &map_to_signal_data(&1, fields))
  end

  alias Jido.Serialization.TypeProvider

  @spec map_to_signal_data(struct, Keyword.t()) :: t()
  def map_to_signal_data(signal, fields) do
    %__MODULE__{
      id: UUID.uuid4(),
      source: "http://example.com/bank",
      jido_causation_id: Keyword.get(fields, :jido_causation_id),
      jido_correlation_id: Keyword.get(fields, :jido_correlation_id),
      type: TypeProvider.to_string(signal),
      data: signal,
      jido_metadata: Keyword.get(fields, :jido_metadata, %{})
    }
  end

  # Parser functions for standard CloudEvents fields
  defp parse_specversion(%{"specversion" => "1.0.2"}), do: :ok
  defp parse_specversion(%{"specversion" => x}), do: {:error, "unexpected specversion #{x}"}
  defp parse_specversion(_), do: {:error, "missing specversion"}

  defp parse_type(%{"type" => type}) when byte_size(type) > 0, do: {:ok, type}
  defp parse_type(_), do: {:error, "missing type"}

  defp parse_source(%{"source" => source}) when byte_size(source) > 0, do: {:ok, source}
  defp parse_source(_), do: {:error, "missing source"}

  defp parse_id(%{"id" => id}) when byte_size(id) > 0, do: {:ok, id}
  defp parse_id(_), do: {:error, "missing id"}

  defp parse_subject(%{"subject" => sub}) when byte_size(sub) > 0, do: {:ok, sub}
  defp parse_subject(%{"subject" => ""}), do: {:error, "subject given but empty"}
  defp parse_subject(_), do: {:ok, nil}

  defp parse_time(%{"time" => time}) when byte_size(time) > 0, do: {:ok, time}
  defp parse_time(%{"time" => ""}), do: {:error, "time given but empty"}
  defp parse_time(_), do: {:ok, nil}

  defp parse_datacontenttype(%{"datacontenttype" => ct}) when byte_size(ct) > 0, do: {:ok, ct}

  defp parse_datacontenttype(%{"datacontenttype" => ""}),
    do: {:error, "datacontenttype given but empty"}

  defp parse_datacontenttype(_), do: {:ok, nil}

  defp parse_dataschema(%{"dataschema" => schema}) when byte_size(schema) > 0, do: {:ok, schema}
  defp parse_dataschema(%{"dataschema" => ""}), do: {:error, "dataschema given but empty"}
  defp parse_dataschema(_), do: {:ok, nil}

  defp parse_data(""), do: {:error, "data field given but empty"}
  defp parse_data(data), do: {:ok, data}

  defp parse_jido_instructions(nil), do: {:ok, nil}

  defp parse_jido_instructions(instructions) do
    case Instruction.normalize(instructions) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _} -> {:error, "jido_instructions must be a list of instructions"}
    end
  end

  defp parse_jido_opts(nil), do: {:ok, %{}}
  defp parse_jido_opts(opts) when is_map(opts), do: {:ok, opts}
  defp parse_jido_opts(_), do: {:error, "jido_opts must be a map"}

  defp parse_correlation_id(nil), do: {:ok, UUID.uuid4()}
  defp parse_correlation_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp parse_correlation_id(""), do: {:error, "correlation_id given but empty"}
  defp parse_correlation_id(_), do: {:error, "correlation_id must be a string"}

  defp parse_causation_id(nil), do: {:ok, UUID.uuid4()}
  defp parse_causation_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp parse_causation_id(""), do: {:error, "causation_id given but empty"}
  defp parse_causation_id(_), do: {:error, "causation_id must be a string"}

  defp parse_jido_dispatch(nil), do: {:ok, nil}

  defp parse_jido_dispatch({adapter, opts} = config) when is_atom(adapter) and is_list(opts) do
    {:ok, config}
  end

  defp parse_jido_dispatch(config) when is_list(config) do
    {:ok, config}
  end

  defp parse_jido_dispatch(_), do: {:error, "invalid dispatch config"}
end
