# Create a simple local file as hello world example
resource "local_file" "hello_world" {
  content  = "Hello, World from tf2 stack!\nGenerated at: ${timestamp()}\n"
  filename = "${path.module}/hello-world.txt"
}