variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  default     = "test"
}

resource "random_id" "test" {
  byte_length = 8
  prefix      = var.name_prefix
}
