# Versions tests for tf2 rules

load(":versions_test.bzl", "versions_test_suite")

versions_test_suite(name = "versions_tests")

test_suite(
    name = "versions_tests_export",
    tests = [":versions_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
