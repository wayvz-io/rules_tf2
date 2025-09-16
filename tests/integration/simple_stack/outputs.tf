# Output the file path
output "hello_world_file" {
  description = "Path to the generated hello world file"
  value       = local_file.hello_world.filename
}

# Output a greeting message
output "greeting" {
  description = "Hello world greeting message"
  value       = "Hello World from tf2 stack!"
}