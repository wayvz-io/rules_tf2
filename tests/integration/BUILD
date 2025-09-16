# Integration tests for tf2 Terraform rules
# These test complete module lifecycles with real Terraform configurations

test_suite(
    name = "all_integration_tests",
    tests = [
        "//tf/tests/integration/simple_module:all",
        "//tf/tests/integration/another_module:all",
        "//tf/tests/integration/module_with_deps:all",
        "//tf/tests/integration/simple_stack:all",
        "//tf/tests/integration/stack_with_modules:all",
        "//tf/tests/integration/hcl_versions_test:all",
        "//tf/tests/integration/filesystem_mirror:all",
        "//tf/tests/integration/tf_lock_integration:all",
    ],
    visibility = ["//visibility:public"],
)