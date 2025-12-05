load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

# HCL types package
go_library(
    name = "hcl_pkg",
    srcs = [
        "pkg/hcl/schema.go",
        "pkg/hcl/types.go",
    ],
    importpath = "github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/hcl",
    visibility = ["//visibility:public"],
    deps = [
        "@com_github_hashicorp_hcl_v2//:hcl",
        "@com_github_hashicorp_hcl_v2//gohcl",
        "@com_github_hashicorp_hcl_v2//hclsyntax",
        "@com_github_hashicorp_hcl_v2//hclwrite",
        "@com_github_zclconf_go_cty//cty",
    ],
)

# Terraform utilities package
go_library(
    name = "terraform_pkg",
    srcs = [
        "pkg/terraform/lockfile.go",
        "pkg/terraform/merger.go",
        "pkg/terraform/reader.go",
        "pkg/terraform/reorganize.go",
        "pkg/terraform/validator.go",
        "pkg/terraform/writer.go",
    ],
    importpath = "github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/terraform",
    visibility = ["//visibility:public"],
    deps = [
        ":hcl_pkg",
        "@com_github_hashicorp_hcl_v2//:hcl",
        "@com_github_hashicorp_hcl_v2//hclparse",
        "@com_github_hashicorp_hcl_v2//hclsyntax",
        "@com_github_hashicorp_hcl_v2//hclwrite",
        "@com_github_zclconf_go_cty//cty",
    ],
)

# Commands package
go_library(
    name = "cmd",
    srcs = [
        "cmd/extract_module_lock.go",
        "cmd/parse_lock.go",
        "cmd/read_versions.go",
        "cmd/reorganize.go",
        "cmd/root.go",
        "cmd/validate_versions.go",  # Contains update-versions command
        "cmd/write_versions.go",
    ],
    importpath = "github.com/wayvz-io/rules_tf2/go/hcl_tool/cmd",
    visibility = ["//visibility:public"],
    deps = [
        ":hcl_pkg",
        ":terraform_pkg",
        "@com_github_spf13_cobra//:cobra",
    ],
)

# Main binary
go_library(
    name = "hcl_tool_lib",
    srcs = ["main.go"],
    importpath = "github.com/wayvz-io/rules_tf2/go/hcl_tool",
    visibility = ["//visibility:private"],
    deps = [":cmd"],
)

go_binary(
    name = "hcl_tool",
    embed = [":hcl_tool_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "hcl_tool_test",
    size = "small",
    srcs = [
        "test/integration_test.go",
        "test/lockfile_test.go",
        "test/reorganize_test.go",
        "test/versions_test.go",
    ],
    deps = [
        ":hcl_pkg",
        ":terraform_pkg",
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
    ],
)
