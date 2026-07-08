# Holds the bot's current position per symbol (0 = flat, 1 = long),
# plus the entry price when long. One item per symbol -- simple and
# cheap, and this is the only table the Lambda needs to read on every
# invocation to know what it did last time.
resource "aws_dynamodb_table" "bot_state" {
  name         = "trading-bot-state-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed for this volume
  hash_key     = "symbol"

  attribute {
    name = "symbol"
    type = "S"
  }

  tags = {
    Project     = "crypto-trading-bot"
    Environment = var.environment
  }
}

# Append-only log of every simulated trade the bot has made. This is
# what you'd query to compute realized P&L, review trade history, or
# eventually feed back into a refined backtest.
resource "aws_dynamodb_table" "bot_trades" {
  name         = "trading-bot-trades-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "trade_id"

  attribute {
    name = "trade_id"
    type = "S"
  }

  tags = {
    Project     = "crypto-trading-bot"
    Environment = var.environment
  }
}
