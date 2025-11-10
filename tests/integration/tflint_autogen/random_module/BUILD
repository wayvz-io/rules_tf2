load("//tf2:def.bzl", "tf_module")

# Random provider module test for TFLint auto-generation
tf_module(
    name = "random_module",
    testonly = True,
    module_tags = ["test_module"],
    providers = ["@tf_provider_registry//:random_3"],
    visibility = ["//tests/integration/tflint_autogen:__pkg__"],
)
