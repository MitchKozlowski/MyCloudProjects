provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "test_bucket" {
  bucket = "testbuckettestbucket1647832609812"

  tags = {
    Name = "MyTestBucket"
  }
}