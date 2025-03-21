defmodule Jido.ExecAction do
  alias Jido.Error

  require OK

  @action_schema NimbleOptions.new!(
                     steps: [
                       type: {:list, {:tuple, [:atom, :atom]}},
                       required: true,
                       doc:
                         "A list of tuples {step_name, action_module} defining the action steps."
                     ],
                     on_complete: [
                       type: :atom,
                       required: false,
                       doc:
                         "Optional callback or action to execute when all steps complete successfully."
                     ],
                     on_failure: [
                       type: :atom,
                       required: false,
                       doc: "Optional callback or action to execute when any step fails."
                     ]
                   )

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@action_config_schema)

    quote location: :keep do
    end
  end
end
