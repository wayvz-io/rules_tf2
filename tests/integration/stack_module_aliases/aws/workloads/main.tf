# AWS workloads module
variable "name" {
  type        = string
  description = "Name for AWS resources"
}

output "aws_result" {
  value = "aws-${var.name}"
}
