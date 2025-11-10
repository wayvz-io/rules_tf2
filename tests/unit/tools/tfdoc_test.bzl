"""Unit tests for tfdoc.bzl functions"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/tools/runners:tfdoc.bzl", "create_tfdoc_generator", "create_tfdoc_test")

def _test_tfdoc_public_api(ctx):
    """Test tfdoc.bzl public API functions exist."""
    env = unittest.begin(ctx)

    # Test that all public functions exist
    asserts.true(env, create_tfdoc_test != None, "create_tfdoc_test should exist")
    asserts.true(env, create_tfdoc_generator != None, "create_tfdoc_generator should exist")

    return unittest.end(env)

def _test_tfdoc_function_types(ctx):
    """Test tfdoc functions have correct types."""
    env = unittest.begin(ctx)

    # Verify functions exist and have correct types
    asserts.true(env, create_tfdoc_test != None, "create_tfdoc_test should exist")
    asserts.true(env, create_tfdoc_generator != None, "create_tfdoc_generator should exist")

    # Check they are not None
    asserts.true(env, str(type(create_tfdoc_test)) != "NoneType", "create_tfdoc_test should not be None")
    asserts.true(env, str(type(create_tfdoc_generator)) != "NoneType", "create_tfdoc_generator should not be None")

    return unittest.end(env)

def _test_tfdoc_module_exports(ctx):
    """Test that the module exports expected symbols."""
    env = unittest.begin(ctx)

    # Check that key functions are exported
    expected_functions = [
        create_tfdoc_test,
        create_tfdoc_generator,
    ]

    for func in expected_functions:
        asserts.true(env, func != None, "Function should exist and be exported")

    return unittest.end(env)

# Test cases
tfdoc_public_api_test = unittest.make(_test_tfdoc_public_api)
tfdoc_function_types_test = unittest.make(_test_tfdoc_function_types)
tfdoc_module_exports_test = unittest.make(_test_tfdoc_module_exports)

def tfdoc_test_suite():
    """Create tfdoc test suite."""
    unittest.suite(
        "tfdoc_tests",
        tfdoc_public_api_test,
        tfdoc_function_types_test,
        tfdoc_module_exports_test,
    )
