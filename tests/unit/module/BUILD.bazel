# Module tests for tf2 rules

load(":module_test.bzl", "module_test_suite")

module_test_suite(name = "module_tests")

test_suite(
    name = "module_tests_export",
    tests = [":module_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
