# Organization tests for tf2 rules

load(":organization_test.bzl", "organization_test_suite")

organization_test_suite(name = "organization_tests")

test_suite(
    name = "organization_tests_export",
    tests = [":organization_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
