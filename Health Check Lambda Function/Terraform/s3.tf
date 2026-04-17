resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "config_bucket" {
  bucket = "health-monitor-config-${random_id.suffix.hex}"
}

resource "aws_s3_object" "servers_config" {
  bucket = aws_s3_bucket.config_bucket.id
  key    = "servers.json"
  source = "servers.json"
  etag   = filemd5("servers.json")
}