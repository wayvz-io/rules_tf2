# Simple tests for tf2 rules

load(":simple_test.bzl", "simple_test_suite")

simple_test_suite(name = "simple_tests")

test_suite(
    name = "simple_tests_export",
    tests = [":simple_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
