provider "random" {}

terraform {
  required_providers {
    random = {
      # Missing source - should trigger lint error
      version = "~> 3.7"
    }
  }
}
