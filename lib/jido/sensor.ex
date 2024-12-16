defmodule Jido.Sensor do
  @moduledoc """
  Defines the behavior and implementation for Sensors in the Jido system.

  A Sensor is a GenServer that emits Signals on PubSub based on specific events and retains a configurable number of last values.
  """

  alias Jido.Error
  alias Jido.Sensor

  require OK

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          category: atom(),
          tags: [atom()],
          vsn: String.t(),
          schema: NimbleOptions.t()
        }

  @type options :: [
          id: String.t(),
          topic: String.t(),
          heartbeat_interval: non_neg_integer(),
          pubsub: module(),
          retain_last: pos_integer()
        ]

  @sensor_compiletime_options_schema NimbleOptions.new!(
                                       name: [
                                         type: {:custom, Jido.Util, :validate_name, []},
                                         required: true
                                       ],
                                       description: [type: :string, required: false],
                                       category: [type: :atom, required: false],
                                       tags: [type: {:list, :atom}, default: []],
                                       vsn: [type: :string, required: false],
                                       schema: [type: :keyword_list, default: []]
                                     )

  defstruct [:name, :description, :category, :tags, :vsn, :schema]

  @callback mount(map()) :: {:ok, map()} | {:error, any()}
  @callback generate_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
  @callback before_publish(Jido.Signal.t(), map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
  @callback shutdown(map()) :: {:ok, map()} | {:error, any()}

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@sensor_compiletime_options_schema)

    quote location: :keep do
      # @behaviour Sensor

      use GenServer

      require Logger
      require OK

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          @sensor_runtime_options_schema NimbleOptions.new!(
                                           [
                                             id: [type: :string],
                                             topic: [
                                               type: :string,
                                               default: "#{@validated_opts[:name]}:${id}"
                                             ],
                                             heartbeat_interval: [
                                               type: :non_neg_integer,
                                               default: 10_000
                                             ],
                                             pubsub: [type: :atom, required: true],
                                             retain_last: [type: :pos_integer, default: 10]
                                           ] ++ @validated_opts[:schema]
                                         )

          def start_link(opts) do
            {id, opts} = Keyword.pop(opts, :id, Jido.Util.generate_id())
            GenServer.start_link(__MODULE__, Map.new(Keyword.put(opts, :id, id)))
          end

          @impl GenServer
          def init(opts) do
            Process.flag(:trap_exit, true)

            with {:ok, validated_opts} <- validate_opts(opts),
                 {:ok, mount_state} <- mount(validated_opts) do
              state =
                Map.merge(mount_state, %{
                  id: validated_opts.id,
                  topic: validated_opts.topic,
                  heartbeat_interval: validated_opts.heartbeat_interval,
                  pubsub: validated_opts.pubsub,
                  sensor: struct(Sensor, @validated_opts),
                  last_values: :queue.new(),
                  retain_last: validated_opts.retain_last
                })

              schedule_heartbeat(state)
              {:ok, state}
            end
          end

          @impl GenServer
          def handle_info(:heartbeat, state) do
            with {:ok, signal} <- generate_signal(state),
                 {:ok, validated_signal} <- before_publish(signal, state),
                 :ok <- publish_signal(validated_signal, state) do
              schedule_heartbeat(state)
              {:noreply, state}
            else
              {:error, reason} ->
                Logger.warning("Error generating or publishing signal: #{inspect(reason)}")
                schedule_heartbeat(state)
                {:noreply, state}
            end
          end

          @impl GenServer
          def handle_info({:sensor_signal, signal}, state) do
            new_state = update_last_values(state, signal)
            {:noreply, new_state}
          end

          @impl GenServer
          def handle_info(msg, state) do
            Logger.debug("Received unhandled message: #{inspect(msg)}")
            {:noreply, state}
          end

          @impl GenServer
          def handle_call(:get_last_values, _from, state) do
            {:reply, :queue.to_list(state.last_values), state}
          end

          @impl GenServer
          def terminate(_reason, state) do
            case shutdown(state) do
              {:ok, _} -> :ok
              {:error, reason} -> Logger.warning("Error during shutdown: #{inspect(reason)}")
            end
          end

          @doc """
          Returns the last N published values.
          """
          @spec get_last_values(pid(), pos_integer()) :: [Jido.Signal.t()]
          def get_last_values(pid, n \\ 10) do
            pid
            |> GenServer.call(:get_last_values)
            |> Enum.take(n)
          end

          defp validate_opts(opts) do
            case NimbleOptions.validate(Map.to_list(opts), @sensor_runtime_options_schema) do
              {:ok, validated} ->
                OK.success(Map.new(validated))

              {:error, %NimbleOptions.ValidationError{} = error} ->
                OK.failure(Sensor.format_validation_error(error))
            end
          end

          defp schedule_heartbeat(%{heartbeat_interval: interval}) when interval > 0 do
            Process.send_after(self(), :heartbeat, interval)
          end

          defp schedule_heartbeat(_), do: :ok

          defp publish_signal(%Jido.Signal{} = signal, state) do
            Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:sensor_signal, signal})
          rescue
            exception ->
              Logger.error("Failed to publish signal: #{inspect(exception)}")
              {:error, :publish_failed}
          end

          defp update_last_values(state, signal) do
            new_queue = :queue.in(signal, state.last_values)

            new_queue =
              if :queue.len(new_queue) > state.retain_last do
                {_, q} = :queue.out(new_queue)
                q
              else
                new_queue
              end

            %{state | last_values: new_queue}
          end

          # Default implementations
          @spec mount(map()) :: {:ok, map()} | {:error, any()}
          def mount(opts), do: OK.success(opts)

          @spec generate_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
          def generate_signal(state) do
            OK.success(
              Jido.Signal.new(%{
                source: "#{state.sensor.name}:#{state.id}",
                topic: "heartbeat",
                payload: %{status: :ok},
                timestamp: DateTime.utc_now()
              })
            )
          end

          @spec before_publish(Jido.Signal.t(), map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
          def before_publish(signal, _state), do: OK.success(signal)

          @spec shutdown(map()) :: {:ok, map()} | {:error, any()}
          def shutdown(state), do: OK.success(state)

          @doc """
          Returns metadata about the sensor.
          """
          @spec metadata() :: Sensor.t()
          def metadata, do: struct(Sensor, @validated_opts)

          @doc """
          Converts the sensor metadata to a JSON-compatible map.
          """
          @spec to_json() :: map()
          def to_json do
            metadata()
            |> Map.from_struct()
            |> Map.update!(:tags, &Enum.map(&1, fn tag -> Atom.to_string(tag) end))
            |> Map.update!(:category, &if(&1, do: Atom.to_string(&1)))
          end

          def __sensor_metadata__ do
            to_json()
          end

          defoverridable mount: 1,
                         generate_signal: 1,
                         handle_info: 2,
                         before_publish: 2,
                         shutdown: 1

        {:error, error} ->
          error
          |> Sensor.format_config_error()
          |> Error.config_error()
          |> OK.error()
      end
    end
  end

  @doc false
  def validate_sensor_config!(_module, opts) do
    case NimbleOptions.validate(opts, @sensor_compiletime_options_schema) do
      {:ok, config} ->
        struct!(__MODULE__, Map.new(config))

      {:error, %NimbleOptions.ValidationError{} = error} ->
        error
        |> format_validation_error()
        |> Error.config_error()
        |> OK.failure()
    end
  end

  @spec format_config_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_config_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    "Invalid configuration given to use Jido.Sensors.Sensor: #{message}"
  end

  def format_config_error(%NimbleOptions.ValidationError{keys_path: keys_path, message: message}) do
    "Invalid configuration given to use Jido.Sensors.Sensor for key #{inspect(keys_path)}: #{message}"
  end

  def format_config_error(error) when is_binary(error), do: error
  def format_config_error(error), do: inspect(error)

  @spec format_validation_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_validation_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    "Invalid parameters for Sensor: #{message}"
  end

  def format_validation_error(%NimbleOptions.ValidationError{
        keys_path: keys_path,
        message: message
      }) do
    "Invalid parameters for Sensor at #{inspect(keys_path)}: #{message}"
  end

  def format_validation_error(error) when is_binary(error), do: error
  def format_validation_error(error), do: inspect(error)
end
