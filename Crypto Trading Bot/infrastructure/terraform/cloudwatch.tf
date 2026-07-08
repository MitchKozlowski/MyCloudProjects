# Fires if the Lambda errors even once in a 24h evaluation window --
# for a bot that only runs once a day, a single failure means that
# day's trade decision was silently skipped, which is worth knowing
# about immediately rather than discovering days later.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "trading-bot-lambda-errors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 86400 # 24 hours, matching the daily invocation cadence
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Trading bot Lambda failed on its most recent invocation."
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.trading_bot.function_name
  }

  alarm_actions = [aws_sns_topic.trade_alerts.arn]
}
