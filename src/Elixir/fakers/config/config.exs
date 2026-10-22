# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# 文書のプロセス: 更新を DB に書くまでの debounce と、何も来ないときに止まるまでの時間
config :fakers, Fakers.Documents, flush_ms: 1_000, idle_ms: 600_000

config :fakers,
  ecto_repos: [Fakers.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :fakers, FakersWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FakersWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Fakers.PubSub,
  live_view: [signing_salt: "lqCL5M/4"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
