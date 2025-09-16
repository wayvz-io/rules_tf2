# Core rule unit tests

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load(":nested_modules_test.bzl", "nested_modules_test_suite")
load(":provider_validation_test.bzl", "provider_validation_test_suite")

# Test suites
nested_modules_test_suite(name = "nested_modules_tests")
provider_validation_test_suite(name = "provider_validation_tests")

# Aggregate core tests
test_suite(
    name = "all",
    tests = [
        ":nested_modules_tests",
        ":provider_validation_tests",
    ],
    visibility = ["//visibility:public"],
)