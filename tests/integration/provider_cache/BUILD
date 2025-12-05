"""Integration test for per-module provider caching"""

load("//tf2/macros:tf_module.bzl", "tf_module")

# Module that uses only the null provider
# This tests that the per-module provider mirror only includes null,
# not all providers from the global registry
tf_module(
    name = "cache_test_module",
    srcs = glob(["*.tf"]) + ["README.md"],
    providers = [
        "@tf_provider_registry//:null_3",
    ],
    tags = ["provider_cache"],
)

# Verify the per-module mirror exists and has the right structure
sh_test(
    name = "provider_cache_structure_test",
    srcs = ["verify_cache_structure.sh"],
    data = [
        ":cache_test_module_provider_mirror",
    ],
    size = "small",
    tags = ["provider_cache"],
)
