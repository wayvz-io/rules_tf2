# TFLint configuration for organization tests

# Disable terraform plugin to avoid rule name conflicts
plugin "terraform" {
  enabled = false
}

# Enable tf2 plugin for organization tests
plugin "tf2" {
  enabled = true
}

# Enable the file organization rule
rule "tf2_terraform_file_organization" {
  enabled = true
}
