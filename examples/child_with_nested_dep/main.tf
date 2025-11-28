# Child Module with Nested Dependency
# This module references the grandchild module

# Use grandchild module with relative path
module "grandchild" {
  # This should be rewritten to ./modules/grandchild when staged in parent
  source = "../nested_dependency_test"

  grandchild_value = var.child_value
}

resource "null_resource" "child" {
  triggers = {
    grandchild_id = module.grandchild.grandchild_id
    child_value   = var.child_value
  }
}
