terraform {
  required_version = ">= 1.13.2"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.6.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}
