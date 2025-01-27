import Config

config :logger, :console,
  format: "[$level] $message\n",
  level: :debug,
  metadata: [:agent_id, :correlation_id, :causation_id],
  metadata_filter: [:agent_id, :correlation_id, :causation_id]

config :logger, level: :debug
