# Data for python: last trades, postion, previous data
import pandas as pd


# Function responsible for receiving data from Elixir and passing it to
# the functions that are responsible for strategical calculations
def execute_strategy(data, position, SMA_S, SMA_L):
    df = initialize_dataframe(data)
    order = []
    if df["complete"].iloc[-1] == True:
        prepared_data = define_strategy(df, SMA_S, SMA_L)
        [order, position] = execute_trades(prepared_data, order, position)

    return [order, position]

# Recieve entry json an return dataframe expected by the implemented strategy
def initialize_dataframe(data):
    df = import_dataframe(data)
    df.set_index("close_time", inplace = True)
    return df

# Convert encoded binary json to a pandas dataframe with the correct units
def import_dataframe(df):
    df = pd.read_json(df.decode('utf-8'))
    datetimes = ["start_time", "close_time"]
    numerics = ["open_price", "high_price", "low_price", "close_price", "number_of_trades", "quote_asset_volume", "number_of_trades"]
    for column in datetimes: df[column] = pd.to_datetime(df[column], unit = "ms")
    for column in numerics: df[column] = pd.to_numeric(df[column])
    return df


# Simple Moving Average strategy implementation
def define_strategy(df, SMA_S, SMA_L):
    #******************** define your strategy here ************************
    data = df[["close_price"]].copy()

    data["SMA_S"] = data.close_price.rolling(window = SMA_S).mean()
    data["SMA_L"] = data.close_price.rolling(window = SMA_L).mean()

    data.dropna(inplace = True)

    cond1 = (data.SMA_S > data.SMA_L)
    cond2 = (data.SMA_S < data.SMA_L)

    data["position"] = 0
    data.loc[cond1, "position"] = 1
    data.loc[cond2, "position"] = -1
    #***********************************************************************

    prepared_data = data.copy()

    return prepared_data

# Decision tree to buy, sell or stay based on strategy
# Order output is a list with the following structure: [side, type, quantity]
def execute_trades(prepared_data, order, position):
    # TODO: implement dynamically generated quantity to buy/sell
    quantity = 1
    if prepared_data["position"].iloc[-1] == 1: # if position is long -> go/stay long
        if position == 0:
            order = ["BUY", "MARKET", quantity]
        elif position == -1:
            order = ["BUY", "MARKET", 2*quantity]
        position = 1
    elif prepared_data["position"].iloc[-1] == 0: # if position is neutral -> go/stay neutral
        if position == 1:
            order = ["SELL", "MARKET", quantity]
        elif position == -1:
            order = ["BUY", "MARKET", quantity]
        position = 0
    if prepared_data["position"].iloc[-1] == -1: # if position is short -> go/stay short
        if position == 0:
            order = ["SELL", "MARKET", quantity]
        elif position == 1:
            order = ["SELL", "MARKET", 2*quantity]
        position = -1
    return [order, position]
