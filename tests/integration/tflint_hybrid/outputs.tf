# This should trigger organization validation - outputs should be in outputs.tf
output "test_output" {
  value = var.test_variable
}

output "availability_zones" {
  value = data.aws_availability_zones.available.names
}
