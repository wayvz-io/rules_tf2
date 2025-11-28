"""Unit tests for tf_test empty directory detection"""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# The error message that terraform outputs when initialized in an empty directory
EMPTY_DIR_MESSAGE = "Terraform initialized in an empty directory"

def _empty_dir_message_detection_test_impl(ctx):
    """Test that we can correctly detect the empty directory message."""
    env = unittest.begin(ctx)

    # Test case 1: Message is present - should be detected
    terraform_output_with_error = """
Terraform initialized in an empty directory!

The directory has no Terraform configuration files. You may begin working
with Terraform immediately by creating Terraform configuration files.
"""
    contains_error = EMPTY_DIR_MESSAGE in terraform_output_with_error
    asserts.true(
        env,
        contains_error,
        "Should detect empty directory message in terraform output",
    )

    # Test case 2: Normal successful output - should not be detected
    terraform_output_success = """
Initializing provider plugins...
- Reusing previous version of hashicorp/random from the dependency lock file
- Installing hashicorp/random v3.7.2...
- Installed hashicorp/random v3.7.2 (signed by HashiCorp)

Terraform has been successfully initialized!
"""
    contains_error_success = EMPTY_DIR_MESSAGE in terraform_output_success
    asserts.false(
        env,
        contains_error_success,
        "Should not detect empty directory message in successful terraform output",
    )

    # Test case 3: Empty output - should not be detected
    terraform_output_empty = ""
    contains_error_empty = EMPTY_DIR_MESSAGE in terraform_output_empty
    asserts.false(
        env,
        contains_error_empty,
        "Should not detect empty directory message in empty output",
    )

    return unittest.end(env)

def _message_substring_test_impl(ctx):
    """Test that substring matching works correctly for error detection."""
    env = unittest.begin(ctx)

    # The exact substring we check for
    check_string = "Terraform initialized in an empty directory"

    # Test various terraform outputs
    test_cases = [
        ("Terraform initialized in an empty directory!", True),
        ("Terraform initialized in an empty directory", True),
        ("terraform initialized in an empty directory!", False),  # Case sensitive
        ("Initializing Terraform in an empty directory", False),  # Different wording
        ("Terraform has been successfully initialized!", False),
    ]

    for output, expected in test_cases:
        actual = check_string in output
        asserts.equals(
            env,
            expected,
            actual,
            "Checking if '{}' contains empty dir message: expected {}, got {}".format(
                output[:50],
                expected,
                actual,
            ),
        )

    return unittest.end(env)

def _staged_files_validation_test_impl(ctx):
    """Test that file staging logic concepts are correct."""
    env = unittest.begin(ctx)

    # Test package path extraction logic
    # This mimics the logic in tf_test_impl for determining relative paths

    # Simulate a source file path and package
    test_package = "tests/integration/simple_module"
    src_path_in_package = "tests/integration/simple_module/main.tf"
    src_path_outside = "external/some_dep/file.tf"

    # Test in-package detection
    in_package = src_path_in_package.startswith(test_package + "/")
    asserts.true(env, in_package, "File in package should be detected")

    # Test relative path extraction
    if in_package:
        relative_path = src_path_in_package[len(test_package) + 1:]
        asserts.equals(env, "main.tf", relative_path, "Relative path should be just the filename")

    # Test outside package detection
    outside_package = src_path_outside.startswith(test_package + "/")
    asserts.false(env, outside_package, "File outside package should not match")

    return unittest.end(env)

# Create test rules
empty_dir_message_detection_test = unittest.make(_empty_dir_message_detection_test_impl)
message_substring_test = unittest.make(_message_substring_test_impl)
staged_files_validation_test = unittest.make(_staged_files_validation_test_impl)

def empty_dir_detection_test_suite(name):
    """Test suite for tf_test empty directory detection.

    Args:
        name: Name of the test suite
    """
    unittest.suite(
        name,
        partial.make(empty_dir_message_detection_test, size = "small"),
        partial.make(message_substring_test, size = "small"),
        partial.make(staged_files_validation_test, size = "small"),
    )
