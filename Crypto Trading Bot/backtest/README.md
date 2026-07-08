# Crypto trading bot — backtest phase

This is step 1 of the trading bot project: validate a strategy against
historical data *before* wiring up any AWS infrastructure or live
paper trading. Everything here runs locally.

## Setup

```bash
pip install pandas numpy requests matplotlib
```

## Step 1: Get real historical data

Binance's public API needs no key for market data. Run this on your
own machine (not inside a sandboxed environment without internet
access to api.binance.com):

```bash
python data/fetch_binance_data.py --symbol BTCUSDT --interval 1h --days 730
```

This saves `data/BTCUSDT_1h.csv` with 2 years of hourly candles.
Swap `--symbol` for any pair Binance lists (ETHUSDT, SOLUSDT, etc.),
and `--interval` for 1m/5m/15m/1h/4h/1d.

## Step 2 (optional): Generate synthetic test data

If you want to sanity-check the code without hitting a real API:

```bash
python data/generate_sample_data.py
```

This is a random walk, NOT real market data — only use it to confirm
the pipeline runs, never to evaluate a strategy's real edge.

## Step 3: Run the backtest

```bash
python run_backtest.py --data data/BTCUSDT_1h.csv --strategy ema
python run_backtest.py --data data/BTCUSDT_1h.csv --strategy rsi
```

This prints a performance report and saves an equity curve chart
(`equity_curve.png`) comparing the strategy against simple buy-and-hold.

### What to look at

- **Total return vs. buy & hold** — if your strategy can't beat just
  holding the asset, it's not adding value yet.
- **Max drawdown** — the worst peak-to-trough loss. This tells you the
  worst-case pain you'd have sat through.
- **Win rate** — percentage of trades that were profitable. A low win
  rate isn't automatically bad if winners are much bigger than losers,
  but it's a flag to look closer.
- **Sharpe ratio** — risk-adjusted return. Roughly: above 1 is decent,
  above 2 is good, negative means the strategy lost money on a
  risk-adjusted basis.
- **Number of trades** — more trades means more fee drag. A strategy
  that "wins" on paper but trades constantly can lose to fees in
  reality.

## Project structure

```
crypto-bot-backtest/
├── data/
│   ├── fetch_binance_data.py    # pulls real OHLCV history from Binance
│   └── generate_sample_data.py  # synthetic data for testing only
├── backtest/
│   ├── strategy.py              # signal logic (reusable in live bot later)
│   └── engine.py                # simulates trades, computes metrics
├── run_backtest.py              # CLI entry point
└── README.md
```

## Why strategy logic is separated from the backtest engine

`backtest/strategy.py` only outputs a `position` column (0 or 1) — it
doesn't know anything about backtesting, fees, or execution. This
means the exact same function can later be dropped into the AWS
Lambda for live paper trading without rewriting the trading logic
itself. Only the execution layer around it changes.

## Next steps

Once a strategy shows a real edge here (beats buy & hold with a
reasonable drawdown across multiple time periods and assets, not just
one lucky backtest window):

1. Tune parameters (fast/slow EMA periods, RSI thresholds) — but watch
   for overfitting to this specific dataset.
2. Test on out-of-sample data (a period you didn't use for tuning).
3. Move to the AWS architecture: EventBridge + Lambda + DynamoDB +
   CloudWatch/SNS, running the same strategy function against live
   (but simulated/paper) trades.
