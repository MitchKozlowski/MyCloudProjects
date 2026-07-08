# Serverless Crypto Trading Bot (AWS + Terraform + Python)

A systematically-validated, serverless crypto trading bot built on
AWS. Paper trading only — no real funds are ever moved. This project
is as much about the *validation process* as the final bot: several
strategies and hypotheses were tested and rejected along the way,
and that process is documented honestly below rather than only
showing the result that worked.

## TL;DR

- Backtested 3 strategy types (EMA crossover, RSI mean-reversion,
  Donchian channel breakout) across multiple assets, timeframes, and
  market regimes
- Found that trading fees, not bad signals, were the dominant cause
  of underperformance early on — fixed by trading less often
- Rejected two hypotheses along the way ("active strategy protects
  better in downturns," "high-frequency trading can compound quickly")
  after the data didn't support them
- Landed on a Donchian breakout strategy (20/10 period, daily candles)
  on SOL/USDT that beat buy-and-hold on both return and drawdown in
  out-of-sample testing
- Deployed it as a serverless AWS bot (Lambda + EventBridge + DynamoDB
  + SNS, fully defined in Terraform) that paper-trades once daily

## Why this project

I wanted a portfolio project that combined my cloud/infrastructure
background (AWS, Terraform, serverless architecture) with a genuine
data problem, rather than a toy CRUD app. Quantitative trading
strategy validation turned out to be a great fit: it forces
discipline around backtesting rigor, honest reporting of negative
results, and separating "this looks good" from "this is actually
robust."

## Architecture

```
EventBridge (daily cron)
        │
        ▼
   Lambda function ──► Binance.US public API (price data, no key needed)
        │
        ├──► DynamoDB: bot state (current position, entry price)
        ├──► DynamoDB: trade log (every simulated trade)
        └──► SNS ──► email (trade alerts + error alarms)
```

Fully serverless, fully Terraform-provisioned, and the Lambda has zero
third-party Python dependencies (pure `urllib` + `boto3`), so no
Lambda layer is needed.

## The validation process

This is the part most write-ups skip, and it's the part that actually
matters. Summarized chronologically:

| Step | Test | Result |
|---|---|---|
| 1 | EMA crossover, hourly BTC candles, real fees | **-36.56%** vs. buy-and-hold's +12.29% — fees were eating the strategy alive (587 trades in 2 years) |
| 2 | Same strategy, zero fees | **+14.29%**, beating buy-and-hold — confirmed fee drag, not bad signals, was the core problem |
| 3 | Wider EMA periods (50/200) + real fees | Trade count dropped 587→109, return improved to **-1.04%** — fewer, higher-quality signals |
| 4 | Switched to daily candles, EMA 20/50 | **+22.17%** vs. buy-and-hold's +14.09%, Sharpe 2.33 — first real edge |
| 5 | Same strategy, 4-year window (includes 2022 bear market) | **+87.43%** vs. buy-and-hold's +195.24% — lagged badly in absolute terms, but max drawdown was -40.86% vs. buy-and-hold's -53.02% |
| 6 | Hypothesis: "strategy protects better specifically during downturns" | **Rejected.** Tested in isolation on the 2022 bear window: strategy lost *more* than buy-and-hold (-28.17% vs -23.5%), 0% win rate on 4 trades |
| 7 | Hypothesis: "high-frequency trading can compound quickly" (targeting large daily gains) | **Rejected.** 15-minute breakout trading on SOL over 60 real days: best single day was +4.29%, not the 40%+ that would be needed — average daily return was actually negative |
| 8 | Donchian breakout (20/10), daily candles, SOL/USDT | **Held up.** -9.61% vs. buy-and-hold's -37.41% in a declining market, drawdown -40.83% vs. -76.26%. Best result across every test run. |

The throughline: every time a strategy looked good, the next test was
designed to try to break it — different asset, different time window,
zero fees vs. real fees, bull vs. bear regime. Most "edges" didn't
survive that process. The one that did became the deployed strategy.

## What the deployed strategy actually is

**Donchian channel breakout** (the core signal behind the old Turtle
Trading system): go long when price closes at a new 20-day high, exit
to flat when it closes at a new 10-day low. Trades on daily candles,
SOL/USDT, no leverage, no shorting.

It is *not* a high-return or fast strategy — the honest finding from
this project is that no systematic, disciplined approach tested here
came close to rapid, large gains without taking on leverage or
concentrated bets that carry a real chance of total loss. What this
strategy does is capture a meaningful chunk of an asset's upside while
avoiding a real portion of its downside, based on the out-of-sample
evidence above.

## Repo structure

```
crypto-trading-bot/
├── backtest/              # Strategy research and validation
│   ├── run_backtest.py    # CLI entry point
│   ├── backtest/
│   │   ├── strategy.py    # EMA, RSI, and Donchian breakout signal logic
│   │   └── engine.py      # Trade simulation, fees, drawdown, daily P&L stats
│   ├── data/
│   │   ├── fetch_binance_data.py   # Real historical OHLCV from Binance.US
│   │   └── generate_sample_data.py # Synthetic data for testing the pipeline
│   └── requirements.txt
│
└── infrastructure/        # Serverless paper-trading deployment
    ├── lambda/
    │   └── handler.py     # Live signal check, matches backtest logic exactly
    └── terraform/         # Full IaC: Lambda, EventBridge, DynamoDB, SNS, IAM, CloudWatch
```

## Running the backtest yourself

```bash
cd backtest
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

python data/fetch_binance_data.py --symbol SOLUSDT --interval 1d --days 730
python run_backtest.py --data data/SOLUSDT_1d.csv --strategy breakout --entry-period 20 --exit-period 10
```

Full option reference (fees, stop-loss, date-range filtering for
regime testing, alternate strategies) is in `backtest/README.md`.

## Deploying the bot

```bash
cd infrastructure/terraform
terraform init
terraform apply -var="alert_email=you@example.com"
```

Full details, including how to confirm the SNS subscription and check
on the bot's state, are in `infrastructure/README.md`.

## Stack

Python (pandas, numpy, matplotlib), AWS Lambda, Amazon EventBridge,
DynamoDB, SNS, CloudWatch, Terraform, Binance.US public API.

## Disclaimer

This is a research and infrastructure portfolio project, not
investment advice. It currently runs in paper-trading mode only. Past
backtest performance does not guarantee future results, and none of
the strategies here have been validated across enough market cycles
or assets to be considered production-ready for real capital.
