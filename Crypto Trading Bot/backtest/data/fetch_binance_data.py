"""
Fetch historical OHLCV candle data from Binance's public API.

No API key required for market data endpoints. Run this locally --
Binance's API is not reachable from network-sandboxed environments,
so this script needs to be run on your own machine or in your AWS
Lambda (where outbound internet access is available).

Note: api.binance.com returns HTTP 451 (blocked) for US-based IP
addresses due to regulatory restrictions. If you're in the US, use
the default --exchange binance.us instead, which mirrors the same
API but has no such restriction.

Usage:
    python fetch_binance_data.py --symbol BTCUSDT --interval 1h --days 365
    python fetch_binance_data.py --symbol BTCUSDT --interval 1h --days 365 --exchange binance.com
"""

import argparse
import time
from datetime import datetime, timedelta, timezone

import pandas as pd
import requests

BINANCE_ENDPOINTS = {
    "binance.com": "https://api.binance.com/api/v3/klines",
    "binance.us": "https://api.binance.us/api/v3/klines",
}

# Binance limits each request to 1000 candles, so we page backwards in time
MAX_CANDLES_PER_REQUEST = 1000

COLUMNS = [
    "open_time", "open", "high", "low", "close", "volume",
    "close_time", "quote_asset_volume", "num_trades",
    "taker_buy_base_volume", "taker_buy_quote_volume", "ignore",
]


def interval_to_timedelta(interval: str) -> timedelta:
    unit = interval[-1]
    value = int(interval[:-1])
    if unit == "m":
        return timedelta(minutes=value)
    if unit == "h":
        return timedelta(hours=value)
    if unit == "d":
        return timedelta(days=value)
    raise ValueError(f"Unsupported interval: {interval}")


def fetch_klines(symbol: str, interval: str, start_time: datetime, end_time: datetime, base_url: str) -> pd.DataFrame:
    """Page through Binance's klines endpoint to build a full history."""
    all_rows = []
    step = interval_to_timedelta(interval) * MAX_CANDLES_PER_REQUEST
    cursor = start_time

    while cursor < end_time:
        chunk_end = min(cursor + step, end_time)
        params = {
            "symbol": symbol,
            "interval": interval,
            "startTime": int(cursor.timestamp() * 1000),
            "endTime": int(chunk_end.timestamp() * 1000),
            "limit": MAX_CANDLES_PER_REQUEST,
        }
        resp = requests.get(base_url, params=params, timeout=15)
        resp.raise_for_status()
        rows = resp.json()
        if rows:
            all_rows.extend(rows)
        cursor = chunk_end
        time.sleep(0.25)  # stay well under Binance's rate limit

    df = pd.DataFrame(all_rows, columns=COLUMNS)
    if df.empty:
        return df

    df["open_time"] = pd.to_datetime(df["open_time"], unit="ms", utc=True)
    for col in ["open", "high", "low", "close", "volume"]:
        df[col] = df[col].astype(float)

    return df[["open_time", "open", "high", "low", "close", "volume"]]


def main():
    parser = argparse.ArgumentParser(description="Fetch historical OHLCV data from Binance")
    parser.add_argument("--symbol", default="BTCUSDT", help="Trading pair, e.g. BTCUSDT")
    parser.add_argument("--interval", default="1h", help="Candle interval: 1m, 5m, 1h, 4h, 1d, etc.")
    parser.add_argument("--days", type=int, default=365, help="How many days of history to fetch")
    parser.add_argument("--out", default=None, help="Output CSV path (default: data/<symbol>_<interval>.csv)")
    parser.add_argument(
        "--exchange", choices=BINANCE_ENDPOINTS.keys(), default="binance.us",
        help="binance.us works from US IPs; binance.com blocks US IPs (HTTP 451) for regulatory reasons"
    )
    args = parser.parse_args()

    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(days=args.days)
    out_path = args.out or f"data/{args.symbol}_{args.interval}.csv"
    base_url = BINANCE_ENDPOINTS[args.exchange]

    print(f"Fetching {args.symbol} {args.interval} candles from {args.exchange} for the last {args.days} days...")
    df = fetch_klines(args.symbol, args.interval, start_time, end_time, base_url)
    df.to_csv(out_path, index=False)
    print(f"Saved {len(df)} candles to {out_path}")


if __name__ == "__main__":
    main()
