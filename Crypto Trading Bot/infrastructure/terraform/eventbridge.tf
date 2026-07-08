# Fires once daily since the strategy trades on daily candles. There's
# no benefit to checking more often than a new candle actually closes
# -- the signal literally cannot change between invocations if
# nothing new has happened.
resource "aws_cloudwatch_event_rule" "daily_trigger" {
  name                = "trading-bot-daily-trigger-${var.environment}"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "invoke_lambda" {
  rule = aws_cloudwatch_event_rule.daily_trigger.name
  arn  = aws_lambda_function.trading_bot.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trading_bot.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_trigger.arn
}
