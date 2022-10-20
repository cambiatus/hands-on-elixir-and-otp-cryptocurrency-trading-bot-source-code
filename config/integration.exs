import Config

config :binance_mock,
  use_cached_exchange_info: true

config :streamer, Streamer.Repo, database: "streamer_test"

config :trader, Trader.Repo, database: "trader_test"

config :data_warehouse, DataWarehouse.Repo, database: "data_warehouse_test"
