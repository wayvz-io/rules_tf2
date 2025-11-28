# Validation tests for tf2 rules

load(":validation_test.bzl", "validation_test_suite")

validation_test_suite(name = "validation_tests")

test_suite(
    name = "validation_tests_export",
    tests = [":validation_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
