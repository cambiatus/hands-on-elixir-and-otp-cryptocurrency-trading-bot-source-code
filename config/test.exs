import Config

config :core,
  logger: Test.LoggerMock,
  pubsub_client: Test.PubSubMock

config :trader,
  exchange_client: Test.BinanceMock,
  leader: Test.Trader.LeaderMock,
  repo: Test.Trader.RepoMock
