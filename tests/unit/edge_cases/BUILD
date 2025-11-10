# Edge case unit tests

load(":error_conditions_test.bzl", "error_conditions_test_suite")

# Test suites
error_conditions_test_suite(name = "error_conditions_tests")

# Aggregate edge case tests
test_suite(
    name = "all",
    tests = [
        ":error_conditions_tests",
    ],
    visibility = ["//visibility:public"],
)
