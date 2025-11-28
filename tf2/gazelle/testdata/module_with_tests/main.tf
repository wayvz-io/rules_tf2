resource "random_id" "test" {
  byte_length = 8
}

output "id" {
  value = random_id.test.hex
}
