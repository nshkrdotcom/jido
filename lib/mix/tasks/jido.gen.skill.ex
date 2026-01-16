if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Jido.Gen.Skill do
    @shortdoc "Generates a Jido Skill module"

    @moduledoc """
    Generates a Jido Skill module.

        $ mix jido.gen.skill MyApp.Skills.Chat

    ## Options

    - `--signals` - Comma-separated list of signal patterns (default: none)

    ## Examples

        $ mix jido.gen.skill MyApp.Skills.Chat
        $ mix jido.gen.skill MyApp.Skills.Chat --signals="chat.*,message.*"
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido,
        positional: [:module],
        schema: [
          signals: :string
        ],
        defaults: [
          signals: nil
        ],
        example: "mix jido.gen.skill MyApp.Skills.Chat"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      positional = igniter.args.positional

      module_name = positional[:module]
      module = Igniter.Project.Module.parse(module_name)
      name = Jido.Igniter.Helpers.module_to_name(module_name)
      state_key = name

      signal_patterns = Jido.Igniter.Helpers.parse_list(options[:signals])

      patterns_str =
        signal_patterns
        |> Enum.map(&~s("#{&1}"))
        |> Enum.join(", ")

      contents = """
      defmodule #{inspect(module)} do
        use Jido.Skill,
          name: "#{name}",
          state_key: :#{state_key},
          actions: [],
          schema: Zoi.object(%{}),
          signal_patterns: [#{patterns_str}]

        @impl Jido.Skill
        def router(_config) do
          []
        end
      end
      """

      test_module_name = "JidoTest.#{module_name |> String.replace(~r/^.*?\./, "")}"
      test_module = Igniter.Project.Module.parse(test_module_name)

      skill_alias = module |> Module.split() |> List.last()

      test_contents = """
      defmodule #{inspect(test_module)} do
        use ExUnit.Case, async: true

        alias #{inspect(module)}

        describe "skill_spec/1" do
          test "returns skill specification" do
            spec = #{skill_alias}.skill_spec(%{})
            assert spec.module == #{skill_alias}
            assert spec.name == #{skill_alias}.name()
          end
        end

        describe "mount/2" do
          test "returns default state" do
            assert {:ok, %{}} = #{skill_alias}.mount(nil, %{})
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
