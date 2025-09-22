# Unit tests for tf2 Bazel rules

# Aggregate all unit tests from subdirectories
test_suite(
    name = "all_unit_tests",
    tests = [
        "//tests/unit/core:all",
        "//tests/unit/edge_cases:all",
        "//tests/unit/format:format_tests",
        "//tests/unit/implicit:all",
        "//tests/unit/lint:lint_tests",
        "//tests/unit/lockfile:lockfile_tests",
        "//tests/unit/module:module_tests",
        "//tests/unit/organization:organization_tests",
        "//tests/unit/provider:provider_tests",
        "//tests/unit/simple:simple_tests",
        "//tests/unit/tflint_config:tflint_config_tests",
        "//tests/unit/validation:validation_tests",
        "//tests/unit/versions:versions_tests",
    ],
    visibility = ["//visibility:public"],
)
