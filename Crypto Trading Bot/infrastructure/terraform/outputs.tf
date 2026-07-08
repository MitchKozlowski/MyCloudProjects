output "lambda_function_name" {
  value = aws_lambda_function.trading_bot.function_name
}

output "state_table_name" {
  value = aws_dynamodb_table.bot_state.name
}

output "trades_table_name" {
  value = aws_dynamodb_table.bot_trades.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.trade_alerts.arn
}

output "next_steps" {
  value = "Check your email and CONFIRM the SNS subscription, or you won't receive any alerts. The Lambda will first run at the next scheduled time (see schedule_expression) -- you can also invoke it manually via the AWS Console or `aws lambda invoke` to test it immediately."
}
