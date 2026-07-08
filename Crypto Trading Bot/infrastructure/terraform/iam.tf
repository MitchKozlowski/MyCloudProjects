# Lambda's execution role -- only trusted to be assumed by the Lambda
# service itself.
resource "aws_iam_role" "lambda_exec" {
  name = "trading-bot-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Project     = "crypto-trading-bot"
    Environment = var.environment
  }
}

# Basic CloudWatch Logs write access -- required for any Lambda to log
# at all, and what the error alarm below reads from.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least-privilege policy: only the specific DynamoDB actions and
# tables the handler actually uses, plus publish-only on the one SNS
# topic. No wildcard resources.
resource "aws_iam_role_policy" "lambda_bot_permissions" {
  name = "trading-bot-permissions-${var.environment}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
        ]
        Resource = [
          aws_dynamodb_table.bot_state.arn,
          aws_dynamodb_table.bot_trades.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.trade_alerts.arn
      }
    ]
  })
}
