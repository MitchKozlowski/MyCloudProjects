# Crypto trading bot — paper trading infrastructure

This deploys the validated strategy from the backtest phase (Donchian
breakout, 20/10 periods, daily candles on SOLUSDT) as a serverless
AWS bot that runs once a day. **It only paper trades** — it never
places a real order or touches real funds. It reads public price
data, decides whether the strategy's signal changed, logs the
simulated trade, and emails you.

## Why this strategy, briefly

Across everything tested in the backtest phase, this was the one
result that actually beat buy-and-hold on both return (-9.61% vs.
-37.41%) and drawdown (-40.83% vs. -76.26%) over a 2-year window on
SOL. It's not a get-rich-quick strategy -- the honest data showed
that isn't realistic for any systematic approach -- but it's the one
configuration that earned its place next to just holding the asset.

## Architecture

```
EventBridge (daily cron)
        │
        ▼
   Lambda function ──► Binance.US public API (price data, no key needed)
        │
        ├──► DynamoDB: bot state (current position, entry price)
        ├──► DynamoDB: trade log (every simulated trade)
        └──► SNS ──► your email (trade alerts + error alarms)
```

All Terraform-provisioned. No third-party Python dependencies in the
Lambda (pure `urllib` + `boto3`, both built into the default Lambda
runtime), so there's no Lambda layer to manage.

## Prerequisites

- AWS account with credentials configured (`aws configure`)
- Terraform >= 1.5 installed locally
- An email address you can confirm a subscription from

## Deploy

```bash
cd terraform
terraform init
terraform plan -var="alert_email=you@example.com"
```

Review the plan. When you're ready:

```bash
terraform apply -var="alert_email=you@example.com"
```

**Important**: check your email right after applying and **confirm
the SNS subscription** — AWS sends a confirmation link, and you won't
receive any alerts until you click it.

## Testing it immediately (don't wait for the daily schedule)

```bash
aws lambda invoke --function-name trading-bot-paper out.json
cat out.json
```

Check CloudWatch Logs (`/aws/lambda/trading-bot-paper`) to see exactly
what it decided and why.

## Customizing

All the strategy parameters are Terraform variables — override them
at apply time rather than editing code:

```bash
terraform apply \
  -var="alert_email=you@example.com" \
  -var="symbol=ETHUSDT" \
  -var="entry_period=20" \
  -var="exit_period=10"
```

If you want to try a different asset, remember to re-validate it in
the backtest first — this strategy's edge was specific to SOL's
volatility profile in the window we tested. Don't assume it transfers.

## Checking on the bot

Query DynamoDB directly to see current state and trade history:

```bash
aws dynamodb get-item \
  --table-name trading-bot-state-paper \
  --key '{"symbol": {"S": "SOLUSDT"}}'

aws dynamodb scan --table-name trading-bot-trades-paper
```

## What this deliberately does NOT do

- **No real order placement.** Wiring this to a real exchange account
  (API keys, order endpoints, real fills) is a separate, deliberate
  step -- don't add it without understanding you're now trading with
  real money and real slippage, not the clean simulated fills a
  backtest assumes.
- **No position sizing beyond "all in / all out."** Real trading
  usually means sizing positions as a percentage of capital, not
  binary fully-invested-or-flat. Worth adding before ever going live.
- **No compounding/portfolio tracking.** The state table tracks
  position and entry price, not a running equity balance. Add that
  if you want the bot to actually report simulated P&L over time
  rather than just "long" or "flat."

## Teardown

```bash
terraform destroy -var="alert_email=you@example.com"
```
