"""
Strategy logic, kept separate from the backtest engine so the same
function can later be dropped into the live Lambda trading loop
unmodified.

Each strategy function takes a DataFrame with at least a 'close' column
and returns the same DataFrame with a 'signal' column added:
    1  = go long / stay long
    0  = flat / no position
   -1  = close long (exit to flat)

Keeping signals in {-1, 0, 1} (rather than directly placing orders)
makes the same function reusable for backtesting, paper trading, and
live trading -- only the execution layer around it changes.
"""

import pandas as pd


def ema_crossover(df: pd.DataFrame, fast: int = 12, slow: int = 26) -> pd.DataFrame:
    """
    Classic trend-following strategy: go long when the fast EMA crosses
    above the slow EMA, exit when it crosses back below.
    """
    df = df.copy()
    df["ema_fast"] = df["close"].ewm(span=fast, adjust=False).mean()
    df["ema_slow"] = df["close"].ewm(span=slow, adjust=False).mean()

    df["position"] = 0
    df.loc[df["ema_fast"] > df["ema_slow"], "position"] = 1

    # signal marks the bar where the position actually changes
    df["signal"] = df["position"].diff().fillna(0)
    return df


def donchian_breakout(df: pd.DataFrame, entry_period: int = 20, exit_period: int = 10) -> pd.DataFrame:
    """
    Classic momentum/breakout strategy (Donchian channel, the core of
    the old Turtle Trading system): go long when price breaks above
    its highest close of the last `entry_period` bars, exit when it
    breaks below its lowest close of the last `exit_period` bars.

    This is a higher-variance style than the EMA crossover -- it's
    designed to catch strong directional moves early, which means more
    false breakouts (small losses) but potentially much larger wins
    when a real move happens. Works best on volatile assets with
    genuine trending behavior, which is why it's worth testing on an
    altcoin rather than BTC.
    """
    df = df.copy()
    df["entry_high"] = df["close"].rolling(entry_period).max()
    df["exit_low"] = df["close"].rolling(exit_period).min()

    df["position"] = 0
    position = 0
    positions = []
    for i in range(len(df)):
        close = df["close"].iloc[i]
        entry_high = df["entry_high"].iloc[i]
        exit_low = df["exit_low"].iloc[i]

        if pd.isna(entry_high) or pd.isna(exit_low):
            positions.append(0)
            continue

        if position == 0 and close >= entry_high:
            position = 1
        elif position == 1 and close <= exit_low:
            position = 0
        positions.append(position)

    df["position"] = positions
    df["signal"] = df["position"].diff().fillna(0)
    return df


def rsi_mean_reversion(df: pd.DataFrame, period: int = 14, oversold: int = 30, overbought: int = 70) -> pd.DataFrame:
    """
    Mean-reversion strategy: buy when RSI drops below the oversold
    threshold, exit when it climbs back above the overbought threshold.
    """
    df = df.copy()
    delta = df["close"].diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)

    avg_gain = gain.rolling(period).mean()
    avg_loss = loss.rolling(period).mean()
    rs = avg_gain / avg_loss
    df["rsi"] = 100 - (100 / (1 + rs))

    df["position"] = 0
    position = 0
    positions = []
    for rsi in df["rsi"]:
        if pd.isna(rsi):
            positions.append(0)
            continue
        if position == 0 and rsi < oversold:
            position = 1
        elif position == 1 and rsi > overbought:
            position = 0
        positions.append(position)
    df["position"] = positions

    df["signal"] = df["position"].diff().fillna(0)
    return df
