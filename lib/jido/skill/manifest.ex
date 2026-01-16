defmodule Jido.Skill.Manifest do
  @moduledoc """
  The manifest representation of a skill's metadata and capabilities.

  Contains all compile-time metadata about a skill for discovery,
  introspection, and ecosystem tooling. Unlike `Jido.Skill.Spec`,
  the manifest focuses on what the skill provides rather than
  per-agent runtime configuration.

  ## Fields

  - `module` - The skill module
  - `name` - Skill name string
  - `description` - Optional description
  - `category` - Optional category for organization
  - `tags` - List of tag strings for categorization
  - `vsn` - Optional version string
  - `capabilities` - List of atoms describing what the skill provides
  - `requires` - List of requirements like `{:config, :token}`, `{:app, :req}`, `{:skill, :http}`
  - `state_key` - Atom key for skill state in agent
  - `schema` - Zoi schema for skill state
  - `config_schema` - Zoi schema for per-agent config
  - `actions` - List of action modules
  - `routes` - List of route tuples like `{"post", ActionModule}`
  - `schedules` - List of schedule tuples like `{"*/5 * * * *", ActionModule}`
  - `signal_patterns` - Legacy signal patterns for routing
  - `subscriptions` - Sensor subscriptions provided by this skill
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              module: Zoi.atom(description: "The skill module"),
              name: Zoi.string(description: "The skill name"),
              description: Zoi.string(description: "Description of the skill") |> Zoi.optional(),
              category: Zoi.string(description: "Category for organization") |> Zoi.optional(),
              tags:
                Zoi.list(Zoi.string(), description: "Tags for categorization") |> Zoi.default([]),
              vsn: Zoi.string(description: "Version string") |> Zoi.optional(),
              otp_app:
                Zoi.atom(description: "OTP application for config resolution") |> Zoi.optional(),
              capabilities:
                Zoi.list(Zoi.atom(), description: "Capabilities provided by the skill")
                |> Zoi.default([]),
              requires:
                Zoi.list(Zoi.any(), description: "Requirements like {:config, :key}")
                |> Zoi.default([]),
              state_key: Zoi.atom(description: "Key for skill state in agent"),
              schema: Zoi.any(description: "Zoi schema for skill state") |> Zoi.optional(),
              config_schema:
                Zoi.any(description: "Zoi schema for per-agent config") |> Zoi.optional(),
              actions:
                Zoi.list(Zoi.atom(), description: "List of action modules") |> Zoi.default([]),
              routes:
                Zoi.list(Zoi.any(), description: "Route tuples like {\"post\", ActionModule}")
                |> Zoi.default([]),
              schedules:
                Zoi.list(Zoi.any(),
                  description: "Schedule tuples like {\"*/5 * * * *\", ActionModule}"
                )
                |> Zoi.default([]),
              signal_patterns:
                Zoi.list(Zoi.string(), description: "Legacy signal patterns")
                |> Zoi.default([]),
              subscriptions:
                Zoi.list(Zoi.any(), description: "Sensor subscriptions provided by this skill")
                |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Manifest."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end
