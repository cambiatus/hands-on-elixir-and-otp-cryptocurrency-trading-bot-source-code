# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :binance_mock,
  use_cached_exchange_info: false

config :core,
  logger: Logger,
  pubsub_client: Phoenix.PubSub

config :data_warehouse,
  ecto_repos: [DataWarehouse.Repo]

config :data_warehouse, DataWarehouse.Repo,
  database: "data_warehouse",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :streamer,
  # binance_client: BinanceMock,
  binance_client: Core.Exchange.Binance,
  ecto_repos: [Streamer.Repo]

config :strategies,
  python_workers: 5,
  python_worker_overflow: 2

config :streamer, Streamer.Repo,
  database: "streamer",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :naive,
  # exchange_client: BinanceMock,
  exchange_client: Core.Exchange.Binance,
  ecto_repos: [Naive.Repo],
  leader: Naive.Leader,
  repo: Naive.Repo,
  trading: %{
    defaults: %{
      chunks: 5,
      budget: 1000,
      buy_down_interval: "0.0001",
      profit_interval: "-0.0012",
      rebuy_interval: "0.001"
    }
  }

config :naive, Naive.Repo,
  database: "naive",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :logger,
  level: :info

# Import secrets file with Binance keys if it exists
if File.exists?("config/secrets.exs") do
  import_config("secrets.exs")
end

import_config "#{config_env()}.exs"
