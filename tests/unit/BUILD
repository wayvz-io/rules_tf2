# Unit tests for tf2 Bazel rules

load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest", "unittest")
load(":simple_test.bzl", "simple_test_suite")
load(":module_test.bzl", "module_test_suite")
load(":provider_test.bzl", "provider_test_suite")
load(":validation_test.bzl", "validation_test_suite")
load(":format_test.bzl", "format_test_suite")
load(":lint_test.bzl", "lint_test_suite")
load(":versions_test.bzl", "versions_test_suite")
load(":organization_test.bzl", "organization_test_suite")
load(":lockfile_test.bzl", "lockfile_test_suite")

# Call all test suites
simple_test_suite(name = "simple_tests")
module_test_suite(name = "module_tests")
provider_test_suite(name = "provider_tests")
validation_test_suite(name = "validation_tests")
format_test_suite(name = "format_tests")
lint_test_suite(name = "lint_tests")
versions_test_suite(name = "versions_tests")
organization_test_suite(name = "organization_tests")
lockfile_test_suite(name = "lockfile_tests")

# Aggregate all unit tests
test_suite(
    name = "all_unit_tests",
    tests = [
        ":simple_tests",
        ":module_tests",
        ":provider_tests",
        ":validation_tests",
        ":format_tests",
        ":lint_tests",
        ":versions_tests",
        ":organization_tests",
        ":lockfile_tests",
        "//tf/tests/unit/core:all",
        "//tf/tests/unit/implicit:all",
        "//tf/tests/unit/edge_cases:all",
    ],
    visibility = ["//visibility:public"],
)