"""Unit tests for platform detection functionality"""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/tools/download:platform.bzl", "PLATFORMS", "TERRAFORM_DOCS_PLATFORMS", "get_terraform_docs_platform")

def _test_platform_configs(ctx):
    """Test platform configuration mappings."""
    env = unittest.begin(ctx)

    # Test that all required platforms are present
    asserts.true(env, "linux" in PLATFORMS, "Linux platform missing")
    asserts.true(env, "macos" in PLATFORMS, "macOS platform missing")

    # Test that all required architectures are present
    asserts.true(env, "amd64" in PLATFORMS["linux"], "Linux amd64 missing")
    asserts.true(env, "arm64" in PLATFORMS["linux"], "Linux arm64 missing")
    asserts.true(env, "amd64" in PLATFORMS["macos"], "macOS amd64 missing")
    asserts.true(env, "arm64" in PLATFORMS["macos"], "macOS arm64 missing")

    # Test platform naming conventions
    asserts.equals(env, PLATFORMS["linux"]["amd64"], "linux_amd64")
    asserts.equals(env, PLATFORMS["linux"]["arm64"], "linux_arm64")
    asserts.equals(env, PLATFORMS["macos"]["amd64"], "darwin_amd64")
    asserts.equals(env, PLATFORMS["macos"]["arm64"], "darwin_arm64")

    return unittest.end(env)

def _test_terraform_docs_platform_conversion(ctx):
    """Test terraform-docs platform conversion."""
    env = unittest.begin(ctx)

    # Test conversion from underscore to dash format
    asserts.equals(env, get_terraform_docs_platform("linux_amd64"), "linux-amd64")
    asserts.equals(env, get_terraform_docs_platform("linux_arm64"), "linux-arm64")
    asserts.equals(env, get_terraform_docs_platform("darwin_amd64"), "darwin-amd64")
    asserts.equals(env, get_terraform_docs_platform("darwin_arm64"), "darwin-arm64")

    # Test terraform-docs platform configuration consistency
    asserts.true(env, "linux" in TERRAFORM_DOCS_PLATFORMS, "Linux platform missing in terraform-docs config")
    asserts.true(env, "macos" in TERRAFORM_DOCS_PLATFORMS, "macOS platform missing in terraform-docs config")

    # Test expected terraform-docs platform naming
    asserts.equals(env, TERRAFORM_DOCS_PLATFORMS["linux"]["amd64"], "linux-amd64")
    asserts.equals(env, TERRAFORM_DOCS_PLATFORMS["macos"]["amd64"], "darwin-amd64")

    return unittest.end(env)

platform_configs_test = unittest.make(_test_platform_configs)
terraform_docs_platform_test = unittest.make(_test_terraform_docs_platform_conversion)

def platform_test_suite():
    """Create platform test suite."""
    unittest.suite(
        "platform_tests",
        partial.make(platform_configs_test, size = "small"),
        partial.make(terraform_docs_platform_test, size = "small"),
    )
