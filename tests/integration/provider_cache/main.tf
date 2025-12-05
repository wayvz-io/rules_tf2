# Simple resource to validate provider works
resource "null_resource" "test" {
  triggers = {
    always_run = timestamp()
  }
}
