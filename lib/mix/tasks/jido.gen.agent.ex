if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Jido.Gen.Agent do
    @shortdoc "Generates a Jido Agent module"

    @moduledoc """
    Generates a Jido Agent module.

        $ mix jido.gen.agent MyApp.Agents.Coordinator

    ## Options

    - `--skills` - Comma-separated list of skill modules to attach (default: none)

    ## Examples

        $ mix jido.gen.agent MyApp.Agents.Coordinator
        $ mix jido.gen.agent MyApp.Agents.Chat --skills=MyApp.Skills.Chat
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido,
        positional: [:module],
        schema: [
          skills: :string
        ],
        defaults: [
          skills: nil
        ],
        example: "mix jido.gen.agent MyApp.Agents.Coordinator"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      positional = igniter.args.positional

      module_name = positional[:module]
      module = Igniter.Project.Module.parse(module_name)
      name = Jido.Igniter.Helpers.module_to_name(module_name)

      skills =
        options[:skills]
        |> Jido.Igniter.Helpers.parse_list()
        |> Enum.map(&String.to_atom/1)

      skills_opt =
        if Enum.empty?(skills) do
          ""
        else
          skills_str = Enum.map_join(skills, ", ", &inspect/1)
          ",\n    skills: [#{skills_str}]"
        end

      contents = """
      defmodule #{inspect(module)} do
        use Jido.Agent,
          name: "#{name}",
          description: "TODO: Add description",
          schema: []#{skills_opt}
      end
      """

      test_module_name = "JidoTest.#{module_name |> String.replace(~r/^.*?\./, "")}"
      test_module = Igniter.Project.Module.parse(test_module_name)

      agent_alias = module |> Module.split() |> List.last()

      test_contents = """
      defmodule #{inspect(test_module)} do
        use ExUnit.Case, async: true

        alias #{inspect(module)}

        describe "new/1" do
          test "creates agent with default state" do
            agent = #{agent_alias}.new()
            assert agent.name == #{agent_alias}.name()
          end

          test "creates agent with custom id" do
            agent = #{agent_alias}.new(id: "custom-id")
            assert agent.id == "custom-id"
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
