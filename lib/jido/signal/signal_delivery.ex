defmodule Jido.Sensor.SignalDelivery do
  @delivery_opts_schema NimbleOptions.new!(
                          target: [
                            type: {:custom, __MODULE__, :validate_delivery_target, []},
                            required: true,
                            doc:
                              "Target for signal delivery. Can be {:pid, pid}, {:bus, bus_name}, {:name, process_name}, or {:remote, {node, target}}"
                          ],
                          delivery_mode: [
                            type: {:in, [:sync, :async]},
                            default: :async,
                            doc: "Delivery mode - :sync for synchronous, :async for asynchronous"
                          ],
                          stream: [
                            type: :string,
                            doc: "Stream name for bus delivery",
                            default: "default"
                          ],
                          version: [
                            type: :any,
                            doc: "Version for bus delivery",
                            default: :any_version
                          ],
                          publish_opts: [
                            type: :keyword_list,
                            doc: "Additional publish options for bus delivery",
                            default: []
                          ]
                        )

  @doc """
  Validates a delivery target value.

  Valid formats:
  - {:pid, pid} - Direct process delivery
  - {:bus, bus_name} - Bus delivery where bus_name is an atom
  - {:name, process_name} - Named process delivery where process_name is an atom
  - {:remote, {node, target}} - Remote node delivery
  """
  def validate_delivery_target({:pid, pid}) when is_pid(pid), do: {:ok, {:pid, pid}}
  def validate_delivery_target({:bus, name}) when is_atom(name), do: {:ok, {:bus, name}}
  def validate_delivery_target({:name, name}) when is_atom(name), do: {:ok, {:name, name}}

  def validate_delivery_target({:remote, {node, target}}) when is_atom(node) do
    case validate_delivery_target(target) do
      {:ok, validated_target} -> {:ok, {:remote, {node, validated_target}}}
      {:error, _} = error -> error
    end
  end

  def validate_delivery_target(_), do: {:error, "invalid delivery target format"}

  def validate_delivery_opts(opts) do
    case NimbleOptions.validate(opts, @delivery_opts_schema) do
      {:ok, validated_opts} -> {:ok, Map.new(validated_opts)}
      error -> error
    end
  end

  def deliver({signal, routing_options}) do
    case routing_options.target do
      {:pid, pid} ->
        do_deliver_to_pid(pid, signal, routing_options)

      {:bus, bus_name} ->
        do_deliver_to_bus(bus_name, signal, routing_options)

      {:name, process_name} ->
        do_deliver_to_named(process_name, signal, routing_options)

      {:remote, {node, target}} ->
        do_deliver_to_remote(node, target, signal, routing_options)
    end
  end

  defp do_deliver_to_pid(pid, signal, %{delivery_mode: :async}) do
    send(pid, {:signal, signal})
    :ok
  end

  defp do_deliver_to_pid(pid, signal, %{delivery_mode: :sync}) do
    GenServer.call(pid, {:signal, signal})
  end

  defp do_deliver_to_bus(bus_name, signal, options) do
    stream = Map.get(options, :stream, "default")
    version = Map.get(options, :version, :any_version)
    publish_opts = Map.get(options, :publish_opts, [])

    case Jido.Bus.publish(bus_name, stream, version, [signal], publish_opts) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp do_deliver_to_named(name, signal, options) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        do_deliver_to_pid(pid, signal, options)

      nil ->
        {:error, :process_not_found}
    end
  end

  defp do_deliver_to_remote(_node, _target, _signal, _options) do
    {:error, :not_implemented}
  end
end
