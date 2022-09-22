from decimal import *
getcontext().prec = 10


def calculate_buy_price(current_price, buy_down_interval, tick_size):
    # not necessarily legal price

    current_price = Decimal(current_price.decode('utf-8'))
    buy_down_interval = Decimal(buy_down_interval.decode('utf-8'))
    tick_size = Decimal(tick_size.decode('utf-8'))

    exact_buy_price = current_price - (current_price*buy_down_interval)

    valid_buy_price = (exact_buy_price//tick_size)*tick_size

    return str(valid_buy_price)


def calculate_quantity(budget, price, step_size):

    budget = Decimal(budget.decode('utf-8'))
    price = Decimal(price.decode('utf-8'))
    step_size = Decimal(step_size.decode('utf-8'))

    # not necessarily legal quantity
    exact_target_quantity = budget/price

    valid_target_quantity = (exact_target_quantity//step_size)*step_size

    return str(valid_target_quantity)


def calculate_sell_price(buy_price, profit_interval, tick_size):
    buy_price = Decimal(buy_price.decode('utf-8'))
    profit_interval = Decimal(profit_interval.decode('utf-8'))
    tick_size = Decimal(tick_size.decode('utf-8'))

    fee = Decimal("1.001")
    original_price = buy_price*fee

    net_target_price = original_price*(1 + profit_interval)

    gross_target_price = net_target_price*fee

    valid_sell_price = (gross_target_price//tick_size)*tick_size

    return str(valid_sell_price)


def init_args(args):
    args = [Decimal(arg.decode('utf-8')) for arg in args]
