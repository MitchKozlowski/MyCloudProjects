output "bucket_name" {
  value = aws_s3_bucket.config_bucket.bucket
}

output "lambda_name" {
  value = aws_lambda_function.health_check.function_name
}