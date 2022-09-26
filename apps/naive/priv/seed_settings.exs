require Logger

alias Decimal
alias Naive.Repo
alias Naive.Schema.Settings

exchange_client = Application.get_env(:naive, :exchange_client)

Logger.info("Fetching exchange info from Binance to create trading settings")

{:ok, %{symbols: symbols}} = exchange_client.fetch_exchange_info()

%{
  chunks: chunks,
  budget: budget,
  buy_down_interval: buy_down_interval,
  profit_interval: profit_interval,
  rebuy_interval: rebuy_interval
} = Application.get_env(:naive, :trading).defaults

timestamp = NaiveDateTime.utc_now()
  |> NaiveDateTime.truncate(:second)

base_settings = %{
  symbol: "",
  chunks: chunks,
  budget: Decimal.new(budget),
  buy_down_interval: Decimal.new(buy_down_interval),
  profit_interval: Decimal.new(profit_interval),
  rebuy_interval: Decimal.new(rebuy_interval),
  status: "off",
  inserted_at: timestamp,
  updated_at: timestamp
}

Logger.info("Inserting default settings for symbols")

maps = Enum.map(symbols, &(%{base_settings | symbol: Map.get(&1, "symbol")}))

{count, nil} = Repo.insert_all(Settings, maps)

Logger.info("Inserted settings for #{count} symbols")
