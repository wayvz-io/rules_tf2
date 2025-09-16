# Output the random string value
output "random_value" {
  description = "The generated random string"
  value       = random_string.test.result
}

# Output a greeting message
output "greeting" {
  description = "Hello world greeting message"
  value       = "Hello from tf2 module!"
}