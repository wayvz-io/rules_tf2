resource "random_id" "test" {
  byte_length = 8
  prefix      = var.name_prefix
}
