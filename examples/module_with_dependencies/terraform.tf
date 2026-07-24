terraform {
  required_version = ">= 1.13.2"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.100.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }
  }
}
