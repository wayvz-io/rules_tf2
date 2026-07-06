terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }
}

# Use the random provider so TFLint validates it
resource "random_id" "test" {
  byte_length = 8
}
