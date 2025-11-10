load("//tf2:def.bzl", "tf_module")

# Module with explicit TFLint config (should not auto-generate)
tf_module(
    name = "explicit_config_module",
    testonly = True,
    providers = ["@tf_provider_registry//:aws_5"],
    visibility = ["//tests/integration/tflint_autogen:__pkg__"],
)
