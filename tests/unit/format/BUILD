# Format tests for tf2 rules

load(":format_test.bzl", "format_test_suite")

format_test_suite(name = "format_tests")

# Export test suite for parent packages
test_suite(
    name = "format_tests_export",
    tests = [":format_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
