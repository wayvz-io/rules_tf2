output "label_id" {
  description = "The generated label ID from the external module"
  value       = module.label.id
}

output "label_tags" {
  description = "The generated tags from the external module"
  value       = module.label.tags
}
