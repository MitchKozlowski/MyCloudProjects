"""
Paper-trading Lambda handler.

Runs the same Donchian breakout logic validated in the backtest
(backtest/strategy.py -> donchian_breakout), but as a live signal check
against the most recent candles rather than a full historical
vectorized pass. Written in pure Python (no pandas/requests) so it
runs in the default Lambda runtime with no layers required.

This is PAPER TRADING ONLY: it never places a real order. It reads
price data from the exchange's public market-data endpoint (no API
key, no account access), decides whether the strategy's signal has
changed, logs the simulated trade to DynamoDB, and sends an SNS alert.
Wiring this to real order placement is a deliberate, separate step
that should only happen after real-money risk is something you've
decided to take on.
"""

import json
import os
import urllib.request
import urllib.error
from decimal import Decimal
from datetime import datetime, timezone

import boto3

dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")

STATE_TABLE = os.environ["STATE_TABLE"]
TRADES_TABLE = os.environ["TRADES_TABLE"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

SYMBOL = os.environ.get("SYMBOL", "SOLUSDT")
INTERVAL = os.environ.get("INTERVAL", "1d")
ENTRY_PERIOD = int(os.environ.get("ENTRY_PERIOD", "20"))
EXIT_PERIOD = int(os.environ.get("EXIT_PERIOD", "10"))
BASE_URL = os.environ.get("BINANCE_BASE_URL", "https://api.binance.us/api/v3/klines")


def fetch_recent_closes(symbol: str, interval: str, limit: int) -> list:
    """Pull the most recent `limit` closed candles' close prices."""
    url = f"{BASE_URL}?symbol={symbol}&interval={interval}&limit={limit}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Exchange API error {e.code} fetching {symbol}: {e.reason}") from e

    # Drop the last candle if it's still open (in-progress), so the
    # strategy only ever acts on fully closed bars -- matches how the
    # backtest treats data (no lookahead into a candle that hasn't
    # finished forming yet).
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    closes = [float(c[4]) for c in data if int(c[6]) < now_ms]  # c[6] = close_time
    return closes


def compute_position(closes: list, entry_period: int, exit_period: int, current_position: int) -> int:
    """
    Same rule as backtest/strategy.py::donchian_breakout, evaluated
    only for the most recent closed bar:
      - go long when the latest close breaks above the highest close
        of the prior `entry_period` bars
      - exit to flat when it breaks below the lowest close of the
        prior `exit_period` bars
    """
    needed = max(entry_period, exit_period) + 1
    if len(closes) < needed:
        print(f"Not enough history yet ({len(closes)}/{needed} candles) -- holding current position.")
        return current_position

    latest_close = closes[-1]
    entry_high = max(closes[-entry_period:])
    exit_low = min(closes[-exit_period:])

    if current_position == 0 and latest_close >= entry_high:
        return 1
    if current_position == 1 and latest_close <= exit_low:
        return 0
    return current_position


def get_state(table) -> dict:
    resp = table.get_item(Key={"symbol": SYMBOL})
    return resp.get("Item") or {"symbol": SYMBOL, "position": 0, "entry_price": None}


def save_state(table, position: int, entry_price):
    item = {
        "symbol": SYMBOL,
        "position": position,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    if entry_price is not None:
        item["entry_price"] = Decimal(str(entry_price))
    table.put_item(Item=item)


def log_trade(table, action: str, price: float, position: int):
    table.put_item(Item={
        "trade_id": f"{SYMBOL}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}",
        "symbol": SYMBOL,
        "action": action,
        "price": Decimal(str(round(price, 4))),
        "position": position,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "mode": "paper",
    })


def notify(subject: str, message: str):
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)


def handler(event, context):
    state_table = dynamodb.Table(STATE_TABLE)
    trades_table = dynamodb.Table(TRADES_TABLE)

    state = get_state(state_table)
    current_position = int(state.get("position", 0))

    lookback = max(ENTRY_PERIOD, EXIT_PERIOD) + 5
    closes = fetch_recent_closes(SYMBOL, INTERVAL, lookback)
    latest_close = closes[-1]

    new_position = compute_position(closes, ENTRY_PERIOD, EXIT_PERIOD, current_position)

    if new_position != current_position:
        action = "BUY" if new_position == 1 else "SELL"
        log_trade(trades_table, action, latest_close, new_position)
        save_state(state_table, new_position, latest_close if new_position == 1 else None)
        message = f"{action} {SYMBOL} at ${latest_close:,.2f} -- PAPER TRADE, no real funds moved."
        notify(f"[Paper Trade] {action} {SYMBOL}", message)
        print(message)
    else:
        print(f"No signal change for {SYMBOL}. Position remains {current_position} at close ${latest_close:,.2f}.")

    return {
        "symbol": SYMBOL,
        "position": new_position,
        "latest_close": latest_close,
        "changed": new_position != current_position,
    }
