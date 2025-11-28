load("//tf2:def.bzl", "tf_module")

# Multi-provider module test for TFLint auto-generation
tf_module(
    name = "multi_provider_module",
    testonly = True,
    srcs = glob(["*.tf"]),
    providers = [
        "@tf_provider_registry//:aws_5",
        "@tf_provider_registry//:random_3",
    ],
    visibility = ["//tests/integration/tflint_autogen:__pkg__"],
)
