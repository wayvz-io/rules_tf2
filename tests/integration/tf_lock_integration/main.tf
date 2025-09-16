resource "null_resource" "test" {
  provisioner "local-exec" {
    command = "echo 'Test resource'"
  }
}

resource "local_file" "test" {
  filename = "/tmp/test_file_${timestamp()}"
  content  = "Test content"
}