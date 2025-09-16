terraform {
  required_version = ">= 1.12.2"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}
