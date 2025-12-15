resource "local_file" "config" {
  content  = templatefile("templates/config.tpl", { name = "test" })
  filename = "${path.module}/output.txt"
}

resource "local_file" "settings" {
  content  = file("data/settings.json")
  filename = "${path.module}/settings.txt"
}

locals {
  config_exists = fileexists("${path.module}/data/settings.json")
}
