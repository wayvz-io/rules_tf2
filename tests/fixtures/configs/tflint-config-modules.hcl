config {
    format = "compact"
#    module = true
    force = false
    disabled_by_default = false
}

rule "terraform_comment_syntax" {
    enabled = true
}

rule "terraform_deprecated_index" {
    enabled = true
}

rule "terraform_documented_outputs" {
    enabled = true
}

rule "terraform_documented_variables" {
    enabled = true
}

rule "terraform_empty_list_equality" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
  force   = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

# Disabled because versions are managed by Bazel via versions.json
# External modules don't need version in the module block
rule "terraform_module_version" {
  enabled = false
}

# Disabled because git sources are pinned via versions.json, not a ?ref in source
rule "terraform_module_pinned_source" {
  enabled = false
}
