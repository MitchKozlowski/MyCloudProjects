# Input variables - the "parameters" of this Terraform configuration.
# Equivalent idea to Terraform variables you already used with AWS, or to
# argparse/env vars in a Python script: values that change between
# environments without editing the actual resource definitions.

variable "project_name" {
  description = "Short name used to prefix all resource names"
  type        = string
  default     = "asteroidwatch"
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name, e.g. dev, prod - included in resource names/tags"
  type        = string
  default     = "dev"
}

variable "container_image_tag" {
  description = "Tag of the image in ACR to deploy (e.g. 'latest' or a git SHA)"
  type        = string
  default     = "latest"
}

# `sensitive = true` tells Terraform not to print this value in plan/apply
# output or logs - similar intent to marking something a secret in a CI
# pipeline. It does NOT encrypt it in the state file though - more on that
# in main.tf where it's used.
variable "nasa_api_key" {
  description = "NASA API key, injected into the container as an env var"
  type        = string
  sensitive   = true
}
