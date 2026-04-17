resource "aws_lambda_function" "health_check" {
  function_name = "health-check-monitor"
  role          = aws_iam_role.lambda_role.arn

  runtime = "python3.11"
  handler = "function.lambda_handler"

  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")

  timeout = 10

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.config_bucket.bucket
      KEY_NAME    = "servers.json"
    }
  }
}