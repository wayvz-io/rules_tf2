load("@rules_go//go:def.bzl", "go_binary", "go_library")

# Terraform helper package
go_library(
    name = "terraform",
    srcs = [
        "terraform/runner.go",
        "terraform/ruleset.go",
        "terraform/terraform.go",
    ],
    importpath = "github.com/wayvz-io/rules_tf2/go/tflint_ruleset/terraform",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_hashicorp_hcl_v2//:hcl",
        "@com_github_hashicorp_hcl_v2//hclsyntax",
        "@com_github_hashicorp_hcl_v2//json",
        "@com_github_terraform_linters_tflint_plugin_sdk//hclext",
        "@com_github_terraform_linters_tflint_plugin_sdk//tflint",
        "@com_github_zclconf_go_cty//cty",
    ],
)

# Rules package
go_library(
    name = "rules",
    srcs = [
        "rules/terraform_file_organization.go",
        "rules/terraform_required_providers.go",
    ],
    importpath = "github.com/wayvz-io/rules_tf2/go/tflint_ruleset/rules",
    visibility = ["//visibility:public"],
    deps = [
        ":terraform",
        "@com_github_hashicorp_go_version//:go-version",
        "@com_github_hashicorp_hcl_v2//:hcl",
        "@com_github_hashicorp_terraform_registry_address//:terraform-registry-address",
        "@com_github_terraform_linters_tflint_plugin_sdk//hclext",
        "@com_github_terraform_linters_tflint_plugin_sdk//terraform",
        "@com_github_terraform_linters_tflint_plugin_sdk//tflint",
        "@com_github_zclconf_go_cty//cty",
    ],
)

# Main plugin library
go_library(
    name = "tflint_ruleset_tf2_lib",
    srcs = ["main.go"],
    importpath = "github.com/wayvz-io/rules_tf2/go/tflint_ruleset",
    visibility = ["//visibility:private"],
    deps = [
        ":rules",
        ":terraform",
        "@com_github_terraform_linters_tflint_plugin_sdk//plugin",
        "@com_github_terraform_linters_tflint_plugin_sdk//tflint",
    ],
)

# Binary plugin
go_binary(
    name = "tflint-ruleset-tf2",
    embed = [":tflint_ruleset_tf2_lib"],
    visibility = ["//visibility:public"],
)
