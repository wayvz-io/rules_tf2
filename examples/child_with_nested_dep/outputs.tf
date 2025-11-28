output "child_id" {
  description = "ID of child resource"
  value       = null_resource.child.id
}

output "grandchild_id" {
  description = "ID of grandchild resource (passed through)"
  value       = module.grandchild.grandchild_id
}
