output "simple_module_output" {
  description = "Output from the simple module"
  value       = module.simple
}

output "vpc_id" {
  description = "VPC ID from the external vpc module"
  value       = module.vpc.vpc_id
}