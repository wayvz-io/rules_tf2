# Provider tests for tf2 rules

load(":provider_test.bzl", "provider_test_suite")

provider_test_suite(name = "provider_tests")

test_suite(
    name = "provider_tests_export",
    tests = [":provider_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
