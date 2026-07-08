# Zips up the handler for deployment. Pure Python, no third-party
# dependencies (urllib and boto3 only, both available in the default
# Lambda runtime) -- so no Lambda layer is needed.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_lambda_function" "trading_bot" {
  function_name    = "trading-bot-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      STATE_TABLE      = aws_dynamodb_table.bot_state.name
      TRADES_TABLE     = aws_dynamodb_table.bot_trades.name
      SNS_TOPIC_ARN    = aws_sns_topic.trade_alerts.arn
      SYMBOL           = var.symbol
      INTERVAL         = var.interval
      ENTRY_PERIOD     = tostring(var.entry_period)
      EXIT_PERIOD      = tostring(var.exit_period)
      BINANCE_BASE_URL = var.binance_base_url
    }
  }

  tags = {
    Project     = "crypto-trading-bot"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.trading_bot.function_name}"
  retention_in_days = 30
}
