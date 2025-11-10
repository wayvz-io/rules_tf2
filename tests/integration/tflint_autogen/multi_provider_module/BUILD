load("//tf2:def.bzl", "tf_module")

# Multi-provider module test for TFLint auto-generation
tf_module(
    name = "multi_provider_module",
    testonly = True,
    module_tags = ["test_module"],
    providers = [
        "@tf_provider_registry//:aws_5",
        "@tf_provider_registry//:random_3",
    ],
    tflint_overrides = {
        "terraform_documented_variables": "{\"enabled\": true}",
    },
    visibility = ["//tests/integration/tflint_autogen:__pkg__"],
)
