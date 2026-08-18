terraform {
  required_version = ">= 1.13.2"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "3.3.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.100.0"
    }
  }
}
