output "parent_id" {
  description = "ID of parent resource"
  value       = null_resource.parent.id
}

output "child_id" {
  description = "ID of child resource (passed through)"
  value       = module.child.child_id
}

output "grandchild_id" {
  description = "ID of grandchild resource (passed through from child)"
  value       = module.child.grandchild_id
}
