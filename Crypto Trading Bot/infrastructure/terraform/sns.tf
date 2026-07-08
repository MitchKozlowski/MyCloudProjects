# Single topic for both "a paper trade executed" notifications (from
# the Lambda itself) and "the Lambda errored" alarms (from CloudWatch).
# Splitting these into two topics is a reasonable option later if you
# want trade alerts on your phone but errors only by email, etc.
resource "aws_sns_topic" "trade_alerts" {
  name = "trading-bot-alerts-${var.environment}"

  tags = {
    Project     = "crypto-trading-bot"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.trade_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
