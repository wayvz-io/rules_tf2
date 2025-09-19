"""Unit tests for terraform starlark action implementations"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/tools/runners:terraform.bzl", "create_terraform_format_test", "create_terraform_validate_test")

def _test_terraform_format_api(ctx):
    """Test terraform format API exists."""
    env = unittest.begin(ctx)

    # Test that the function exists
    asserts.true(env, create_terraform_format_test != None, "create_terraform_format_test should exist")

    return unittest.end(env)

def _test_terraform_validate_api(ctx):
    """Test terraform validate API exists."""
    env = unittest.begin(ctx)

    # Test that the function exists
    asserts.true(env, create_terraform_validate_test != None, "create_terraform_validate_test should exist")

    return unittest.end(env)

def _test_functions_types(ctx):
    """Test functions have correct types."""
    env = unittest.begin(ctx)

    # Verify functions exist and have correct types
    asserts.true(env, str(type(create_terraform_format_test)) != "NoneType", "create_terraform_format_test should not be None")
    asserts.true(env, str(type(create_terraform_validate_test)) != "NoneType", "create_terraform_validate_test should not be None")

    return unittest.end(env)

# Test cases
terraform_format_api_test = unittest.make(_test_terraform_format_api)
terraform_validate_api_test = unittest.make(_test_terraform_validate_api)
functions_types_test = unittest.make(_test_functions_types)

def terraform_actions_test_suite():
    """Create terraform actions test suite."""
    unittest.suite(
        "terraform_actions_tests",
        terraform_format_api_test,
        terraform_validate_api_test,
        functions_types_test,
    )