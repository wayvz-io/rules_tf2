# Stack outputs

output "simple_output" {
  description = "Output from the simple module"
  value       = module.simple
}

output "another_output" {
  description = "ID from the another module"
  value       = module.another.id
}