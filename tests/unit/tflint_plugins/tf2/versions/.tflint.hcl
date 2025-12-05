# TFLint config with expected provider versions
config {
  call_module_type = "none"
}

plugin "tf2" {
  enabled = true
}

rule "tf2_terraform_required_providers" {
  enabled = true
  providers = {
    random = {
      source  = "hashicorp/random"
      version = "3.6.0"
    }
  }
}
