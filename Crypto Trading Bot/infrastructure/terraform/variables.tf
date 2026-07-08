variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used as a resource name suffix"
  type        = string
  default     = "paper"
}

variable "symbol" {
  description = "Trading pair symbol on Binance.US, e.g. SOLUSDT"
  type        = string
  default     = "SOLUSDT"
}

variable "interval" {
  description = "Candle interval the strategy trades on"
  type        = string
  default     = "1d"
}

variable "entry_period" {
  description = "Donchian breakout: lookback period for entry (new high)"
  type        = number
  default     = 20
}

variable "exit_period" {
  description = "Donchian breakout: lookback period for exit (new low)"
  type        = number
  default     = 10
}

variable "binance_base_url" {
  description = "Binance klines endpoint. Use binance.us for US-based deployments (binance.com returns HTTP 451 for US IPs)."
  type        = string
  default     = "https://api.binance.us/api/v3/klines"
}

variable "schedule_expression" {
  description = "EventBridge schedule for the Lambda. Default: once daily at 00:05 UTC, shortly after the prior day's daily candle closes."
  type        = string
  default     = "cron(5 0 * * ? *)"
}

variable "alert_email" {
  description = "Email address to receive paper-trade execution alerts and error alarms"
  type        = string
}
