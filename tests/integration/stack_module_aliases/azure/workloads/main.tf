# Azure workloads module
variable "name" {
  type        = string
  description = "Name for Azure resources"
}

output "azure_result" {
  value = "azure-${var.name}"
}
