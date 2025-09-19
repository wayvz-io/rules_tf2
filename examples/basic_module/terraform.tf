terraform {
  required_version = ">= 1.13.2"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.100.0"
    }
  }
}
