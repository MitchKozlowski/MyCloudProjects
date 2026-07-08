"""
Generates a synthetic OHLCV price series for testing the backtest
engine end-to-end without needing network access to Binance.

This is NOT real market data -- it's a random walk with mild upward
drift and volatility clustering, meant only to verify that the
strategy and engine code run correctly and produce sane output.
Swap this out for fetch_binance_data.py's real output before drawing
any conclusions about an actual strategy's edge.
"""

import numpy as np
import pandas as pd


def generate_synthetic_ohlcv(num_bars: int = 24 * 365, start_price: float = 40_000, seed: int = 42) -> pd.DataFrame:
    rng = np.random.default_rng(seed)

    # Random walk with slight drift, plus regime-switching volatility
    # so the series has realistic trending and choppy periods
    returns = np.zeros(num_bars)
    vol = 0.006
    for i in range(num_bars):
        if i % 200 == 0:
            vol = rng.choice([0.003, 0.006, 0.012])
        returns[i] = rng.normal(loc=0.00005, scale=vol)

    close = start_price * np.cumprod(1 + returns)
    high = close * (1 + np.abs(rng.normal(0, 0.002, num_bars)))
    low = close * (1 - np.abs(rng.normal(0, 0.002, num_bars)))
    open_ = np.roll(close, 1)
    open_[0] = start_price
    volume = rng.uniform(100, 1000, num_bars)

    timestamps = pd.date_range(end=pd.Timestamp.now("UTC"), periods=num_bars, freq="h")

    return pd.DataFrame({
        "open_time": timestamps,
        "open": open_,
        "high": high,
        "low": low,
        "close": close,
        "volume": volume,
    })


if __name__ == "__main__":
    df = generate_synthetic_ohlcv()
    df.to_csv("data/SYNTHETIC_1h.csv", index=False)
    print(f"Generated {len(df)} synthetic hourly candles -> data/SYNTHETIC_1h.csv")
