# Simple module example using random provider
resource "random_string" "test" {
  length  = 16
  special = false
}