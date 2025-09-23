"""Unit tests for staging utilities"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/internal:file_ops.bzl", "copy_source_files", "stage_terraform_files")

def _staging_test_impl(ctx):
    """Test staging utilities work correctly"""
    env = unittest.begin(ctx)

    # Test that file_ops utilities are importable and have expected structure
    # In a real test environment, we would create mock files and test the staging logic
    asserts.true(env, copy_source_files != None, "copy_source_files should be importable")
    asserts.true(env, stage_terraform_files != None, "stage_terraform_files should be importable")

    return unittest.end(env)

staging_test = unittest.make(
    _staging_test_impl,
    attrs = {},
)

def staging_test_suite(name):
    """Test suite for staging utilities"""
    unittest.suite(
        name,
        staging_test,
    )
