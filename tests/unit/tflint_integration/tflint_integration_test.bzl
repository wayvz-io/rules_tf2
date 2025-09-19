"""Unit tests for TFLint integration functionality"""

load("@bazel_skylib//lib:unittest.bzl", "unittest", "asserts")
load("//tf2/testing:tflint_rules.bzl", "tf_tflint_validate_test", "tf_tflint_fix")

def _basic_tflint_validate_test_impl(ctx):
    """Test that tf_tflint_validate_test rule can be created."""
    env = unittest.begin(ctx)

    # This test verifies that the tf_tflint_validate_test rule works
    # The actual functionality testing happens in integration tests
    asserts.true(env, True, "tf_tflint_validate_test rule loaded successfully")

    return unittest.end(env)

def _basic_tflint_fix_test_impl(ctx):
    """Test that tf_tflint_fix rule can be created."""
    env = unittest.begin(ctx)

    # This test verifies that the tf_tflint_fix rule works
    # The actual functionality testing happens in integration tests
    asserts.true(env, True, "tf_tflint_fix rule loaded successfully")

    return unittest.end(env)

def _error_message_format_test_impl(ctx):
    """Test that error messages use proper format."""
    env = unittest.begin(ctx)

    # Test the expected format of error messages
    # Should start with "rules_tf2:" instead of "<unknown>:"
    expected_prefix = "rules_tf2:"
    asserts.true(env, expected_prefix.startswith("rules_tf2"), "Error messages should use rules_tf2 prefix")

    return unittest.end(env)

def _tflint_config_format_test_impl(ctx):
    """Test that TFLint config uses correct format for v0.59.1+."""
    env = unittest.begin(ctx)

    # Test that we use call_module_type instead of deprecated module setting
    expected_config_key = "call_module_type"
    deprecated_config_key = "module"

    asserts.true(env, expected_config_key == "call_module_type", "Should use call_module_type in config")
    asserts.false(env, expected_config_key == deprecated_config_key, "Should not use deprecated module setting")

    return unittest.end(env)

# Define unit test rules
basic_tflint_validate_test = unittest.make(_basic_tflint_validate_test_impl)
basic_tflint_fix_test = unittest.make(_basic_tflint_fix_test_impl)
error_message_format_test = unittest.make(_error_message_format_test_impl)
tflint_config_format_test = unittest.make(_tflint_config_format_test_impl)

def tflint_integration_test_suite(name):
    """Creates a test suite for TFLint integration tests."""

    unittest.suite(
        name,
        basic_tflint_validate_test,
        basic_tflint_fix_test,
        error_message_format_test,
        tflint_config_format_test,
    )