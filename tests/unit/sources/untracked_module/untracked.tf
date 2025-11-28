# This file is intentionally not included in srcs for negative testing
resource "null_resource" "untracked" {
  triggers = {
    value = "untracked"
  }
}
