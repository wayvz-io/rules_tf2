# OPA tests for tf2 rules

load(":opa_test.bzl", "opa_test_suite")

opa_test_suite(name = "opa_tests")

# Export for parent test suite
test_suite(
    name = "opa_tests_export",
    tests = [":opa_tests"],
    visibility = ["//tests/unit:__pkg__"],
)
