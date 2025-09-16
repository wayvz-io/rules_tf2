# Test module for HCL-based version management
resource "random_string" "test" {
  length = 16
}

resource "local_file" "test" {
  content  = random_string.test.result
  filename = "${path.module}/test.txt"
}