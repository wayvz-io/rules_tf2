# Sample Terraform Stack component configuration
# This demonstrates a stack that references the simple_module

required_providers {
  random = {
    source  = "hashicorp/random"
    version = "~> 3.0"
  }
  local = {
    source  = "hashicorp/local"
    version = "~> 2.0"
  }
  null = {
    source  = "hashicorp/null"
    version = "~> 3.0"
  }
}

# Main component referencing the simple_module
component "base" {
  source = "../simple_module"

  inputs = {
    name_prefix = var.environment
  }

  providers = {
    random = provider.random.main
    local  = provider.local.main
    null   = provider.null.main
  }
}
