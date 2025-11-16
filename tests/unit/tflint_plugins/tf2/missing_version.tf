provider "random" {}

terraform {
  required_providers {
    random = {
      source = "hashicorp/random"
      # Missing version constraint - should trigger lint error
    }
  }
}
