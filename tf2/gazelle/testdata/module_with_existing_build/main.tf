resource "local_file" "config" {
  content  = templatefile("${path.module}/templates/config.tpl", { name = "test" })
  filename = "/tmp/config.txt"
}
