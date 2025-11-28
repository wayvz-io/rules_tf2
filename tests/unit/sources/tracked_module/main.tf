resource "null_resource" "test" {
  triggers = {
    value = "tracked"
  }
}
