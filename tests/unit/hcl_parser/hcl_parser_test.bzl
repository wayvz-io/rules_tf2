"""Unit tests for HCL parser functions."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/providers/repository:hcl_parser.bzl", "compute_provider_delta", "parse_lock_hcl", "sanitize_provider_key")

# Sample HCL lock file content for testing
_SAMPLE_LOCK_HCL = """
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "6.26.0"
  constraints = "~> 6.0"
  hashes = [
    "h1:0hcNr59VEJbhZYwuDE/ysmyTS0evkfcLarlni+zATPM=",
    "h1:1234567890abcdef1234567890abcdef12345678=",
    "zh:14829603a32e4bc4d05062f059e545a91e27ff033756b48afbae6b3c835f508f",
    "zh:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
  ]
}

provider "registry.terraform.io/hashicorp/random" {
  version     = "3.7.2"
  constraints = "~> 3.0"
  hashes = [
    "h1:randomhash1234567890abcdef=",
    "zh:randomzhhash1234567890abcdef",
  ]
}
"""

_EMPTY_LOCK_HCL = """
# Empty lock file with no providers
"""

_SINGLE_PROVIDER_LOCK_HCL = """
provider "registry.terraform.io/hashicorp/null" {
  version = "3.2.4"
  hashes = [
    "h1:nullhash123=",
    "zh:nullzhhash456",
  ]
}
"""

def _test_parse_lock_hcl_basic_impl(ctx):
    """Test parsing a basic lock file with multiple providers."""
    env = unittest.begin(ctx)

    result = parse_lock_hcl(_SAMPLE_LOCK_HCL)

    # Should have h1 and zh keys
    asserts.true(env, "h1" in result, "Result should have 'h1' key")
    asserts.true(env, "zh" in result, "Result should have 'zh' key")

    # Should have extracted all h1 hashes (without prefix)
    asserts.equals(env, 3, len(result["h1"]), "Should have 3 h1 hashes")
    asserts.true(
        env,
        "0hcNr59VEJbhZYwuDE/ysmyTS0evkfcLarlni+zATPM=" in result["h1"],
        "Should contain first h1 hash",
    )
    asserts.true(
        env,
        "randomhash1234567890abcdef=" in result["h1"],
        "Should contain random provider h1 hash",
    )

    # Should have extracted all zh hashes (without prefix)
    asserts.equals(env, 3, len(result["zh"]), "Should have 3 zh hashes")
    asserts.true(
        env,
        "14829603a32e4bc4d05062f059e545a91e27ff033756b48afbae6b3c835f508f" in result["zh"],
        "Should contain first zh hash",
    )

    return unittest.end(env)

parse_lock_hcl_basic_test = unittest.make(_test_parse_lock_hcl_basic_impl)

def _test_parse_lock_hcl_empty_impl(ctx):
    """Test parsing an empty lock file."""
    env = unittest.begin(ctx)

    result = parse_lock_hcl(_EMPTY_LOCK_HCL)

    asserts.equals(env, [], result["h1"], "Empty file should have no h1 hashes")
    asserts.equals(env, [], result["zh"], "Empty file should have no zh hashes")

    return unittest.end(env)

parse_lock_hcl_empty_test = unittest.make(_test_parse_lock_hcl_empty_impl)

def _test_parse_lock_hcl_single_provider_impl(ctx):
    """Test parsing a lock file with a single provider."""
    env = unittest.begin(ctx)

    result = parse_lock_hcl(_SINGLE_PROVIDER_LOCK_HCL)

    asserts.equals(env, 1, len(result["h1"]), "Should have 1 h1 hash")
    asserts.equals(env, 1, len(result["zh"]), "Should have 1 zh hash")
    asserts.equals(env, "nullhash123=", result["h1"][0], "Should have correct h1 hash")
    asserts.equals(env, "nullzhhash456", result["zh"][0], "Should have correct zh hash")

    return unittest.end(env)

parse_lock_hcl_single_provider_test = unittest.make(_test_parse_lock_hcl_single_provider_impl)

def _test_sanitize_provider_key_impl(ctx):
    """Test provider key sanitization."""
    env = unittest.begin(ctx)

    # Test basic provider key
    asserts.equals(
        env,
        "hashicorp_aws_6_26_0",
        sanitize_provider_key("hashicorp/aws:6.26.0"),
        "Should sanitize hashicorp/aws:6.26.0",
    )

    # Test with longer namespace
    asserts.equals(
        env,
        "myorg_myprovider_1_0_0",
        sanitize_provider_key("myorg/myprovider:1.0.0"),
        "Should sanitize myorg/myprovider:1.0.0",
    )

    # Test with complex version
    asserts.equals(
        env,
        "hashicorp_random_3_7_2",
        sanitize_provider_key("hashicorp/random:3.7.2"),
        "Should sanitize hashicorp/random:3.7.2",
    )

    return unittest.end(env)

sanitize_provider_key_test = unittest.make(_test_sanitize_provider_key_impl)

def _test_compute_provider_delta_all_missing_impl(ctx):
    """Test delta computation when all providers are missing."""
    env = unittest.begin(ctx)

    versions_data = {
        "providers": {
            "hashicorp/aws": ["6.26.0"],
            "hashicorp/random": ["3.7.2"],
        },
    }
    cached_hashes = {}

    delta = compute_provider_delta(versions_data, cached_hashes)

    asserts.equals(env, 2, len(delta["missing"]), "Should have 2 missing providers")
    asserts.true(env, "hashicorp/aws:6.26.0" in delta["missing"], "Should include aws")
    asserts.true(env, "hashicorp/random:3.7.2" in delta["missing"], "Should include random")
    asserts.equals(env, [], delta["obsolete"], "Should have no obsolete providers")
    asserts.equals(env, [], delta["unchanged"], "Should have no unchanged providers")

    return unittest.end(env)

compute_provider_delta_all_missing_test = unittest.make(_test_compute_provider_delta_all_missing_impl)

def _test_compute_provider_delta_all_cached_impl(ctx):
    """Test delta computation when all providers are already cached."""
    env = unittest.begin(ctx)

    versions_data = {
        "providers": {
            "hashicorp/aws": ["6.26.0"],
        },
    }
    cached_hashes = {
        "hashicorp/aws:6.26.0": {"h1": ["hash1"], "zh": ["hash2"]},
    }

    delta = compute_provider_delta(versions_data, cached_hashes)

    asserts.equals(env, [], delta["missing"], "Should have no missing providers")
    asserts.equals(env, [], delta["obsolete"], "Should have no obsolete providers")
    asserts.equals(env, 1, len(delta["unchanged"]), "Should have 1 unchanged provider")

    return unittest.end(env)

compute_provider_delta_all_cached_test = unittest.make(_test_compute_provider_delta_all_cached_impl)

def _test_compute_provider_delta_mixed_impl(ctx):
    """Test delta computation with a mix of missing, cached, and obsolete providers."""
    env = unittest.begin(ctx)

    versions_data = {
        "providers": {
            "hashicorp/aws": ["6.26.0"],  # new
            "hashicorp/random": ["3.7.2"],  # unchanged
        },
    }
    cached_hashes = {
        "hashicorp/random:3.7.2": {"h1": [], "zh": []},  # unchanged
        "hashicorp/null:3.2.4": {"h1": [], "zh": []},  # obsolete (not in versions_data)
    }

    delta = compute_provider_delta(versions_data, cached_hashes)

    asserts.equals(env, 1, len(delta["missing"]), "Should have 1 missing provider")
    asserts.true(env, "hashicorp/aws:6.26.0" in delta["missing"], "aws should be missing")

    asserts.equals(env, 1, len(delta["obsolete"]), "Should have 1 obsolete provider")
    asserts.true(env, "hashicorp/null:3.2.4" in delta["obsolete"], "null should be obsolete")

    asserts.equals(env, 1, len(delta["unchanged"]), "Should have 1 unchanged provider")
    asserts.true(env, "hashicorp/random:3.7.2" in delta["unchanged"], "random should be unchanged")

    return unittest.end(env)

compute_provider_delta_mixed_test = unittest.make(_test_compute_provider_delta_mixed_impl)

def _test_compute_provider_delta_empty_impl(ctx):
    """Test delta computation with empty inputs."""
    env = unittest.begin(ctx)

    versions_data = {"providers": {}}
    cached_hashes = {}

    delta = compute_provider_delta(versions_data, cached_hashes)

    asserts.equals(env, [], delta["missing"], "Should have no missing providers")
    asserts.equals(env, [], delta["obsolete"], "Should have no obsolete providers")
    asserts.equals(env, [], delta["unchanged"], "Should have no unchanged providers")

    return unittest.end(env)

compute_provider_delta_empty_test = unittest.make(_test_compute_provider_delta_empty_impl)

def hcl_parser_test_suite(name):
    """Create all HCL parser test targets.

    Args:
        name: Name of the test suite
    """
    parse_lock_hcl_basic_test(name = "parse_lock_hcl_basic_test")
    parse_lock_hcl_empty_test(name = "parse_lock_hcl_empty_test")
    parse_lock_hcl_single_provider_test(name = "parse_lock_hcl_single_provider_test")
    sanitize_provider_key_test(name = "sanitize_provider_key_test")
    compute_provider_delta_all_missing_test(name = "compute_provider_delta_all_missing_test")
    compute_provider_delta_all_cached_test(name = "compute_provider_delta_all_cached_test")
    compute_provider_delta_mixed_test(name = "compute_provider_delta_mixed_test")
    compute_provider_delta_empty_test(name = "compute_provider_delta_empty_test")

    native.test_suite(
        name = name,
        tests = [
            ":parse_lock_hcl_basic_test",
            ":parse_lock_hcl_empty_test",
            ":parse_lock_hcl_single_provider_test",
            ":sanitize_provider_key_test",
            ":compute_provider_delta_all_missing_test",
            ":compute_provider_delta_all_cached_test",
            ":compute_provider_delta_mixed_test",
            ":compute_provider_delta_empty_test",
        ],
    )
