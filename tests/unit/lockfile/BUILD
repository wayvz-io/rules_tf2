# Lockfile tests for tf2 rules

load(":lockfile_test.bzl", "lockfile_test_suite")

lockfile_test_suite(name = "lockfile_tests")

test_suite(
    name = "lockfile_tests_export",
    tests = [":lockfile_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
