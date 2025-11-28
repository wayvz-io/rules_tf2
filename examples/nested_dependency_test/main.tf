# Grandchild Module
# This is the leaf module that has no dependencies
resource "null_resource" "grandchild" {
  triggers = {
    value = var.grandchild_value
  }
}
