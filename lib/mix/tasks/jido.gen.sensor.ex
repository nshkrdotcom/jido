if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Jido.Gen.Sensor do
    @shortdoc "Generates a Jido Sensor module"

    @moduledoc """
    Generates a Jido Sensor module.

        $ mix jido.gen.sensor MyApp.Sensors.Temperature

    ## Options

    - `--interval` - Polling interval in milliseconds (default: 5000)

    ## Examples

        $ mix jido.gen.sensor MyApp.Sensors.Temperature
        $ mix jido.gen.sensor MyApp.Sensors.Metrics --interval=10000
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido,
        positional: [:module],
        schema: [
          interval: :integer
        ],
        defaults: [
          interval: 5000
        ],
        example: "mix jido.gen.sensor MyApp.Sensors.Temperature"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      positional = igniter.args.positional

      module_name = positional[:module]
      module = Igniter.Project.Module.parse(module_name)
      name = Jido.Igniter.Helpers.module_to_name(module_name)
      interval = options[:interval]

      contents = """
      defmodule #{inspect(module)} do
        use Jido.Sensor,
          name: "#{name}",
          description: "TODO: Add description",
          schema: Zoi.object(%{
            interval: Zoi.integer() |> Zoi.default(#{interval})
          })

        @impl true
        def init(config, _context) do
          interval = config[:interval] || #{interval}
          {:ok, %{interval: interval}, [{:schedule, interval}]}
        end

        @impl true
        def handle_event(:poll, state) do
          # TODO: Implement polling logic
          {:ok, state, []}
        end
      end
      """

      test_module_name = "JidoTest.#{module_name |> String.replace(~r/^.*?\./, "")}"
      test_module = Igniter.Project.Module.parse(test_module_name)

      sensor_alias = module |> Module.split() |> List.last()

      test_contents = """
      defmodule #{inspect(test_module)} do
        use ExUnit.Case, async: true

        alias #{inspect(module)}

        describe "init/2" do
          test "initializes with default interval" do
            assert {:ok, state, directives} = #{sensor_alias}.init(%{}, %{})
            assert is_map(state)
            assert is_list(directives)
          end
        end

        describe "handle_event/2" do
          test "handles poll event" do
            {:ok, state, _} = #{sensor_alias}.init(%{}, %{})
            assert {:ok, _state, signals} = #{sensor_alias}.handle_event(:poll, state)
            assert is_list(signals)
          end
        end
      end
      """

      igniter
      |> Igniter.Project.Module.create_module(module, contents)
      |> Igniter.Project.Module.create_module(test_module, test_contents, location: :test)
    end
  end
end
