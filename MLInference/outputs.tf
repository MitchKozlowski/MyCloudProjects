output "ml_bucket_name" {
  description = "Name of the ML S3 bucket"
  value       = aws_s3_bucket.ml_bucket.id
}

output "ml_bucket_arn" {
  description = "ARN of the ML S3 bucket"
  value       = aws_s3_bucket.ml_bucket.arn
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.arn
}

output "sagemaker_endpoint_name" {
  description = "Name of the SageMaker endpoint"
  value       = aws_sagemaker_endpoint.huggingface_endpoint.name
}

output "sagemaker_endpoint_arn" {
  description = "ARN of the SageMaker endpoint"
  value       = aws_sagemaker_endpoint.huggingface_endpoint.arn
}
