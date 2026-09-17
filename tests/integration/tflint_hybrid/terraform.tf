terraform {
  required_version = ">= 1.13.2"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.60.0"
    }
  }
}
