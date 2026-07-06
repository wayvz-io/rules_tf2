terraform {
  required_version = ">= 1.13.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.26.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}
