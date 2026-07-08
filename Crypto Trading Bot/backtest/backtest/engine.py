"""
Backtest engine: takes a DataFrame with a 'position' column (0 or 1,
produced by a strategy function) and simulates what would have
happened, including trading fees, so results aren't unrealistically
optimistic.
"""

import numpy as np
import pandas as pd


def apply_stop_loss(df: pd.DataFrame, stop_loss_pct: float) -> pd.DataFrame:
    """
    Overlays a hard stop-loss on top of a strategy's raw position signals.

    stop_loss_pct: e.g. 0.10 = exit if price falls 10% below the entry
    price of the current position. This is a simple fixed stop from
    entry (not a trailing stop) -- easy to reason about and a solid
    first line of defense against the kind of deep drawdowns a raw
    trend-following signal can ride all the way down.

    Note: if the underlying strategy's raw signal is still "long" after
    a stop-out, it will re-enter on the very next bar where that signal
    holds. In choppy conditions this can mean multiple stop-outs in a
    row -- worth watching the trade count after adding this.
    """
    df = df.copy()
    raw_position = df["position"].values.copy()
    close = df["close"].values
    adjusted_position = raw_position.copy()

    in_position = False
    entry_price = None

    for i in range(len(df)):
        if adjusted_position[i] == 1 and not in_position:
            in_position = True
            entry_price = close[i]
        elif in_position:
            if raw_position[i] == 0:
                # strategy itself exited
                in_position = False
                entry_price = None
            elif close[i] <= entry_price * (1 - stop_loss_pct):
                # stop-loss triggered: force exit from this bar onward
                # until the raw strategy signal produces a fresh entry
                adjusted_position[i] = 0
                in_position = False
                entry_price = None

    df["position"] = adjusted_position
    df["signal"] = df["position"].diff().fillna(0)
    return df


def compute_daily_stats(df: pd.DataFrame) -> dict:
    """
    Breaks the equity curve into calendar-day returns. This is the real
    answer to 'can this realistically produce big daily gains
    consistently' -- aggregate return over months can hide wild swings
    or make a strategy look steadier than any single day actually was.
    """
    daily = df.set_index("open_time")["equity"].resample("D").last().dropna()
    daily_returns = daily.pct_change().dropna()

    if daily_returns.empty:
        return {
            "num_days": 0, "pct_days_positive": None, "avg_daily_return_pct": None,
            "best_day_pct": None, "worst_day_pct": None, "days_over_10pct": 0, "days_under_neg10pct": 0,
        }

    return {
        "num_days": len(daily_returns),
        "pct_days_positive": round((daily_returns > 0).mean() * 100, 1),
        "avg_daily_return_pct": round(daily_returns.mean() * 100, 3),
        "best_day_pct": round(daily_returns.max() * 100, 2),
        "worst_day_pct": round(daily_returns.min() * 100, 2),
        "days_over_10pct": int((daily_returns > 0.10).sum()),
        "days_under_neg10pct": int((daily_returns < -0.10).sum()),
    }


def run_backtest(df: pd.DataFrame, fee_pct: float = 0.001, initial_capital: float = 10_000) -> dict:
    """
    fee_pct: round-trip cost assumption per side (0.001 = 0.1%, a
    typical Binance spot taker fee). Applied whenever position changes.
    """
    df = df.copy()
    df["market_return"] = df["close"].pct_change().fillna(0)

    # Strategy return is the market return earned only while holding a position.
    # Shift(1) because a signal generated on bar t can only be acted on
    # starting bar t+1 -- you can't trade on information you don't have yet.
    df["strategy_return"] = df["position"].shift(1).fillna(0) * df["market_return"]

    # Subtract fees on the bars where a trade actually happens
    trade_occurred = df["position"].diff().abs().fillna(0) > 0
    df.loc[trade_occurred, "strategy_return"] -= fee_pct

    df["equity"] = initial_capital * (1 + df["strategy_return"]).cumprod()
    df["buy_hold_equity"] = initial_capital * (1 + df["market_return"]).cumprod()

    # Drawdown: how far below the running peak the equity curve has fallen
    running_max = df["equity"].cummax()
    df["drawdown"] = (df["equity"] - running_max) / running_max

    buy_hold_running_max = df["buy_hold_equity"].cummax()
    df["buy_hold_drawdown"] = (df["buy_hold_equity"] - buy_hold_running_max) / buy_hold_running_max

    total_return = df["equity"].iloc[-1] / initial_capital - 1
    buy_hold_return = df["buy_hold_equity"].iloc[-1] / initial_capital - 1
    max_drawdown = df["drawdown"].min()
    buy_hold_max_drawdown = df["buy_hold_drawdown"].min()

    num_trades = int(trade_occurred.sum())
    daily_stats = compute_daily_stats(df)

    # Per-trade win rate: group consecutive holding periods and check
    # whether each one was net profitable
    trade_returns = []
    holding = False
    trade_start_equity = None
    for i in range(len(df)):
        pos = df["position"].iloc[i]
        if pos == 1 and not holding:
            holding = True
            trade_start_equity = df["equity"].iloc[i]
        elif pos == 0 and holding:
            holding = False
            trade_returns.append(df["equity"].iloc[i] / trade_start_equity - 1)
    if holding:
        trade_returns.append(df["equity"].iloc[-1] / trade_start_equity - 1)

    win_rate = (
        sum(1 for r in trade_returns if r > 0) / len(trade_returns)
        if trade_returns else float("nan")
    )

    best_trade = max(trade_returns) if trade_returns else float("nan")
    worst_trade = min(trade_returns) if trade_returns else float("nan")
    # "Blowup" trades: single positions that lost more than 20% -- the
    # kind of individual result that matters most for a high-variance
    # strategy, since aggregate stats can hide how bad the tail gets
    big_losers = sum(1 for r in trade_returns if r < -0.20)

    # Annualized Sharpe ratio, assuming the interval implies a known bar count/year.
    # Caller passes this in via periods_per_year for correctness; default assumes hourly bars.
    returns = df["strategy_return"]
    sharpe = (
        (returns.mean() / returns.std()) * np.sqrt(24 * 365)
        if returns.std() > 0 else float("nan")
    )

    return {
        "df": df,
        "total_return_pct": round(total_return * 100, 2),
        "buy_hold_return_pct": round(buy_hold_return * 100, 2),
        "max_drawdown_pct": round(max_drawdown * 100, 2),
        "buy_hold_max_drawdown_pct": round(buy_hold_max_drawdown * 100, 2),
        "num_trades": num_trades,
        "win_rate_pct": round(win_rate * 100, 2) if not np.isnan(win_rate) else None,
        "best_trade_pct": round(best_trade * 100, 2) if not np.isnan(best_trade) else None,
        "worst_trade_pct": round(worst_trade * 100, 2) if not np.isnan(worst_trade) else None,
        "big_losers": big_losers,
        "sharpe_ratio": round(sharpe, 2) if not np.isnan(sharpe) else None,
        "final_equity": round(df["equity"].iloc[-1], 2),
        "daily_stats": daily_stats,
    }


def print_report(results: dict, strategy_name: str = "Strategy"):
    print(f"\n{'=' * 50}")
    print(f"Backtest results: {strategy_name}")
    print(f"{'=' * 50}")
    print(f"Total return:        {results['total_return_pct']}%")
    print(f"Buy & hold return:   {results['buy_hold_return_pct']}%")
    print(f"Max drawdown:        {results['max_drawdown_pct']}%")
    print(f"Buy & hold drawdown: {results['buy_hold_max_drawdown_pct']}%")
    print(f"Number of trades:    {results['num_trades']}")
    print(f"Win rate:            {results['win_rate_pct']}%")
    print(f"Best single trade:   {results['best_trade_pct']}%")
    print(f"Worst single trade:  {results['worst_trade_pct']}%")
    print(f"Trades that lost >20%: {results['big_losers']}")
    print(f"Sharpe ratio:        {results['sharpe_ratio']}")
    print(f"Final equity:        ${results['final_equity']:,}")

    ds = results["daily_stats"]
    if ds["num_days"] > 0:
        print(f"\n--- Daily breakdown ({ds['num_days']} calendar days) ---")
        print(f"Days positive:       {ds['pct_days_positive']}%")
        print(f"Avg daily return:    {ds['avg_daily_return_pct']}%")
        print(f"Best day:            {ds['best_day_pct']}%")
        print(f"Worst day:           {ds['worst_day_pct']}%")
        print(f"Days with >+10%:     {ds['days_over_10pct']}")
        print(f"Days with <-10%:     {ds['days_under_neg10pct']}")
    print(f"{'=' * 50}\n")
