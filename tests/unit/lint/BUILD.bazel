# Lint tests for tf2 rules

load(":lint_test.bzl", "lint_test_suite")

lint_test_suite(name = "lint_tests")

# Export for parent test suite
test_suite(
    name = "lint_tests_export",
    tests = [":lint_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
