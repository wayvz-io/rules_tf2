terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# This resource has issues that the AWS ruleset should catch
resource "aws_instance" "example" {
  ami           = "ami-12345678"  # This is an invalid AMI ID format
  instance_type = "m5.xlarge"
  
  # Missing security groups (best practice violation)
  # Missing key_name (best practice violation)
}

# This S3 bucket has issues the AWS ruleset should catch
resource "aws_s3_bucket" "example" {
  bucket = "my-example-bucket-123"
  
  # Old-style bucket configuration (deprecated)
  acl = "private"
}