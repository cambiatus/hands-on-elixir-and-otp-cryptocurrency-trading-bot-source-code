defmodule Core.Exchange do
  defmodule SymbolInfo do
    @type t :: %__MODULE__{
            symbol: String.t(),
            tick_size: number(),
            step_size: number()
          }

    defstruct [:symbol, :tick_size, :step_size]
  end

  defmodule Order do
    @type t :: %__MODULE__{
            id: non_neg_integer(),
            symbol: String.t(),
            price: String.t(),
            quantity: String.t(),
            side: String.t(),
            status: String.t(),
            type: String.t(),
            time_in_force: String.t(),
            average_price: String.t(),
            order_id: number(),
            realized_quantity: String.t(),
            position_side: String.t(),
            timestamp: number(),
            trader_id: String.t()
          }

    defstruct [
      :id,
      :symbol,
      :price,
      :quantity,
      :side,
      :status,
      :type,
      :time_in_force,
      :average_price,
      :order_id,
      :realized_quantity,
      :position_side,
      :timestamp,
      :trader_id
    ]
  end

  @callback fetch_symbols() ::
              {:ok, [String.t()]}
              | {:error, any()}
  @callback fetch_symbol_filters(symbol :: String.t()) ::
              {:ok, Core.Exchange.SymbolInfo.t()}
              | {:error, any()}
  @callback get_order(
              symbol :: String.t(),
              timestamp :: non_neg_integer(),
              order_id :: non_neg_integer()
            ) ::
              {:ok, Core.Exchange.Order.t()}
              | {:error, any()}
  @callback order_limit_buy(
              symbol :: String.t(),
              quantity :: number(),
              price :: number(),
              time_in_force :: String.t()
            ) ::
              {:ok, Core.Exchange.Order.t()}
              | {:error, any()}
  @callback order_limit_sell(
              symbol :: String.t(),
              quantity :: number(),
              price :: number(),
              time_in_force :: String.t()
            ) ::
              {:ok, Core.Exchange.Order.t()}
              | {:error, any()}
end
