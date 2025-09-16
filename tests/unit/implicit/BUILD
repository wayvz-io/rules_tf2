# Implicit behavior unit tests

load("@bazel_skylib//lib:unittest.bzl", "unittest")
load(":file_globbing_test.bzl", "file_globbing_test_suite")
load(":version_aggregation_test.bzl", "version_aggregation_test_suite")

# Test suites
file_globbing_test_suite(name = "file_globbing_tests")
version_aggregation_test_suite(name = "version_aggregation_tests")

# Aggregate implicit behavior tests
test_suite(
    name = "all",
    tests = [
        ":file_globbing_tests",
        ":version_aggregation_tests",
    ],
    visibility = ["//visibility:public"],
)