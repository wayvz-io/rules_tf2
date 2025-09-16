# Shared test fixtures and configurations

exports_files([
    "configs/tfdoc-config.yaml",
    "configs/tflint-config-modules.hcl",
    "configs/tflint-config-stacks.hcl",
], visibility = ["//visibility:public"])

filegroup(
    name = "tfdoc-config",
    srcs = ["configs/tfdoc-config.yaml"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "tflint-config-modules",
    srcs = ["configs/tflint-config-modules.hcl"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "tflint-config-stacks", 
    srcs = ["configs/tflint-config-stacks.hcl"],
    visibility = ["//visibility:public"],
)