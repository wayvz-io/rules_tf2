# Stack component demonstrating module_aliases
# Both modules have the same folder name (workloads) but are disambiguated via aliases

# AWS workloads component - aliased to aws_workloads
component "aws" {
  source = "./components/aws_workloads"

  inputs = {
    name = var.environment
  }
}

# Azure workloads component - aliased to azure_workloads
component "azure" {
  source = "./components/azure_workloads"

  inputs = {
    name = var.environment
  }
}
