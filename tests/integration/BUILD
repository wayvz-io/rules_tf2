# Integration tests for tf2 Terraform rules
# These test complete module lifecycles with real Terraform configurations

test_suite(
    name = "all_integration_tests",
    tests = [
        "//tests/integration/another_module:another_module_validate_test",
        "//tests/integration/module_with_deps:module_with_deps_correct_validate_test",
        "//tests/integration/simple_module:simple_module_validate_test",
        "//tests/integration/simple_stack:simple_stack_validate_test",
        "//tests/integration/stack_with_modules:stack_with_modules_validate_test",
    ],
    visibility = ["//visibility:public"],
)
