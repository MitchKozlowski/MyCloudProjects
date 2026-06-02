terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}


# ---- Bucket creation ----
resource "aws_s3_bucket" "ml_bucket" {
  bucket = var.bucket_name

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_versioning" "ml_bucket_versioning" {
  bucket = aws_s3_bucket.ml_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml_bucket_encryption" {
  bucket = aws_s3_bucket.ml_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ml_bucket_public_access" {
  bucket = aws_s3_bucket.ml_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- IAM ----

data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name               = "sagemaker-inference-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}

# Least-privilege S3 access — only this bucket
resource "aws_iam_policy" "sagemaker_s3_policy" {
  name        = "sagemaker-inference-s3-policy"
  description = "Least-privilege S3 access for SageMaker inference"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ml_bucket.arn,
          "${aws_s3_bucket.ml_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach custom S3 policy
resource "aws_iam_role_policy_attachment" "sagemaker_s3_attachment" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = aws_iam_policy.sagemaker_s3_policy.arn
}

# AWS managed policy for SageMaker core functionality
resource "aws_iam_role_policy_attachment" "sagemaker_full_attachment" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}


resource "aws_iam_policy" "sagemaker_monitor_policy" {
  name        = "sagemaker-model-monitor-policy"
  description = "Permissions for SageMaker Model Monitor to write monitoring results"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ml_bucket.arn,
          "${aws_s3_bucket.ml_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_monitor_attachment" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = aws_iam_policy.sagemaker_monitor_policy.arn
}

# ---- SageMaker ----

data "aws_caller_identity" "current" {}

resource "aws_sagemaker_model" "huggingface_model" {
  name               = "huggingface-sentiment-model"
  execution_role_arn = aws_iam_role.sagemaker_execution_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_s3_attachment,
    aws_iam_role_policy_attachment.sagemaker_full_attachment
  ]

  primary_container {
    image = "763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-inference:1.13.1-transformers4.26.0-cpu-py39-ubuntu20.04"

    environment = {
      HF_MODEL_ID      = "distilbert-base-uncased-finetuned-sst-2-english"
      HF_TASK          = "text-classification"
    }
  }

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}

resource "aws_sagemaker_endpoint_configuration" "huggingface_endpoint_config" {
  name = "huggingface-sentiment-endpoint-config"

  production_variants {
    variant_name           = "primary"
    model_name             = aws_sagemaker_model.huggingface_model.name
    initial_instance_count = 1
    instance_type          = "ml.m5.large"
    initial_variant_weight = 1
  }

  data_capture_config {
    enable_capture              = true
    initial_sampling_percentage = 100
    destination_s3_uri          = "s3://${aws_s3_bucket.ml_bucket.id}/data-capture"

    capture_options {
      capture_mode = "Input"
    }

    capture_options {
      capture_mode = "Output"
    }

    capture_content_type_header {
      json_content_types = ["application/json"]
    }
  }

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}

resource "aws_sagemaker_endpoint" "huggingface_endpoint" {
  name                 = "huggingface-sentiment-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.huggingface_endpoint_config.name

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}

# ---- CloudWatch ----

resource "aws_cloudwatch_log_group" "sagemaker_log_group" {
  name              = "/aws/sagemaker/endpoints/huggingface-sentiment-endpoint"
  retention_in_days = 7

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}

resource "aws_cloudwatch_metric_alarm" "endpoint_invocation_errors" {
  alarm_name          = "sagemaker-inference-invocation-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Invocation4XXErrors"
  namespace           = "AWS/SageMaker"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when SageMaker endpoint returns 4XX errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    EndpointName  = aws_sagemaker_endpoint.huggingface_endpoint.name
    VariantName   = "primary"
  }

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}

# ---- Auto Scaling ----

resource "aws_appautoscaling_target" "sagemaker_scaling_target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "endpoint/${aws_sagemaker_endpoint.huggingface_endpoint.name}/variant/primary"
  scalable_dimension = "sagemaker:variant:DesiredInstanceCount"
  service_namespace  = "sagemaker"
}

resource "aws_appautoscaling_policy" "sagemaker_scaling_policy" {
  name               = "sagemaker-inference-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sagemaker_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.sagemaker_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.sagemaker_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "SageMakerVariantInvocationsPerInstance"
    }
  }
}


# ---- Model Monitor ----

resource "aws_sagemaker_monitoring_schedule" "endpoint_monitor" {
  name = "huggingface-sentiment-monitor"

  monitoring_schedule_config {
    monitoring_type = "DataQuality"

    schedule_config {
      schedule_expression = "cron(0 * * * ? *)"
    }

    monitoring_job_definition_name = aws_sagemaker_data_quality_job_definition.data_quality.name
  }

  depends_on = [
    aws_sagemaker_data_quality_job_definition.data_quality
  ]

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}

resource "aws_sagemaker_data_quality_job_definition" "data_quality" {
  name     = "huggingface-sentiment-data-quality"
  role_arn = aws_iam_role.sagemaker_execution_role.arn

  data_quality_app_specification {
    image_uri = "156813124566.dkr.ecr.us-east-1.amazonaws.com/sagemaker-model-monitor-analyzer:latest"
  }

  data_quality_job_input {
    endpoint_input {
      endpoint_name         = aws_sagemaker_endpoint.huggingface_endpoint.name
      local_path            = "/opt/ml/processing/input/endpoint"
      s3_data_distribution_type = "FullyReplicated"
      s3_input_mode         = "File"
    }
  }

  data_quality_job_output_config {
    monitoring_outputs {
      s3_output {
        local_path     = "/opt/ml/processing/output"
        s3_uri         = "s3://${aws_s3_bucket.ml_bucket.id}/monitor-output"
        s3_upload_mode = "EndOfJob"
      }
    }
  }

  job_resources {
    cluster_config {
      instance_count    = 1
      instance_type     = "ml.t3.large"
      volume_size_in_gb = 20
    }
  }

  stopping_condition {
    max_runtime_in_seconds = 3600
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_monitor_attachment,
    aws_sagemaker_endpoint.huggingface_endpoint
  ]

  tags = {
    Project     = "ml-inference"
    Environment = "dev"
  }
}
