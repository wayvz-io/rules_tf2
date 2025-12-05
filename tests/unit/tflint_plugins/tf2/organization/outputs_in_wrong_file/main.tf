resource "random_id" "test" {
  byte_length = 8
}

output "random_id" {
  value       = random_id.test.hex
  description = "Generated random ID"
}
