# Sentinel tests for tf2 rules

load(":sentinel_test.bzl", "sentinel_test_suite")

sentinel_test_suite(name = "sentinel_tests")

# Export for parent test suite
test_suite(
    name = "sentinel_tests_export",
    tests = [":sentinel_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
