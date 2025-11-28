# Parent Module
# This module uses the child module
# It should NOT need to declare grandchild in its modules list

module "child" {
  # This will be rewritten to ./modules/child_with_nested_dep
  source = "../child_with_nested_dep"

  child_value = var.parent_value
}

resource "null_resource" "parent" {
  triggers = {
    child_id     = module.child.child_id
    parent_value = var.parent_value
  }
}
