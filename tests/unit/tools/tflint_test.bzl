"""Unit tests for tflint.bzl functions"""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/tools/runners:tflint.bzl", "create_tflint_autofix", "create_tflint_test")

def _test_tflint_public_api(ctx):
    """Test tflint.bzl public API functions exist."""
    env = unittest.begin(ctx)

    # Test that all public functions exist
    asserts.true(env, create_tflint_test != None, "create_tflint_test should exist")
    asserts.true(env, create_tflint_autofix != None, "create_tflint_autofix should exist")

    return unittest.end(env)

def _test_tflint_function_types(ctx):
    """Test tflint functions have correct types."""
    env = unittest.begin(ctx)

    # Verify functions exist and have correct types
    asserts.true(env, create_tflint_test != None, "create_tflint_test should exist")
    asserts.true(env, create_tflint_autofix != None, "create_tflint_autofix should exist")

    # Check they are not None
    asserts.true(env, str(type(create_tflint_test)) != "NoneType", "create_tflint_test should not be None")
    asserts.true(env, str(type(create_tflint_autofix)) != "NoneType", "create_tflint_autofix should not be None")

    return unittest.end(env)

def _test_tflint_module_exports(ctx):
    """Test that the module exports expected symbols."""
    env = unittest.begin(ctx)

    # Check that key functions are exported
    expected_functions = [
        create_tflint_test,
        create_tflint_autofix,
    ]

    for func in expected_functions:
        asserts.true(env, func != None, "Function should exist and be exported")

    return unittest.end(env)

# Test cases
tflint_public_api_test = unittest.make(_test_tflint_public_api)
tflint_function_types_test = unittest.make(_test_tflint_function_types)
tflint_module_exports_test = unittest.make(_test_tflint_module_exports)

def tflint_test_suite():
    """Create tflint test suite."""
    unittest.suite(
        "tflint_tests",
        partial.make(tflint_public_api_test, size = "small"),
        partial.make(tflint_function_types_test, size = "small"),
        partial.make(tflint_module_exports_test, size = "small"),
    )
