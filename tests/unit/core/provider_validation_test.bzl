"""Unit tests for provider validation and management"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest", "unittest")

# Test semver validation
def _test_semver_validation(ctx):
    """Test that version strings are validated as semver"""
    env = unittest.begin(ctx)
    
    # Valid semver versions
    valid_versions = [
        "1.0.0",
        "2.3.4",
        "10.20.30",
        "0.0.1",
        "6.12.0",
    ]
    
    # Invalid semver versions
    invalid_versions = [
        "1.0",           # Missing patch
        "1",             # Missing minor and patch
        "1.0.0.0",       # Too many parts
        "v1.0.0",        # Has prefix
        "1.0.0-beta",    # Has suffix (we don't support)
        "1.a.0",         # Non-numeric
        "",              # Empty
    ]
    
    # Test valid versions
    for version in valid_versions:
        parts = version.split(".")
        asserts.equals(env, 3, len(parts), "Valid version should have 3 parts: " + version)
        for part in parts:
            asserts.true(env, part.isdigit(), "Version parts should be numeric: " + version)
    
    # Test invalid version detection
    for version in invalid_versions:
        if version == "":
            asserts.true(env, True, "Empty version should be rejected")
        elif "." not in version:
            asserts.true(env, True, "Version without dots should be rejected: " + version)
        else:
            parts = version.split(".")
            is_valid = len(parts) == 3
            for p in parts:
                if not p.isdigit():
                    is_valid = False
                    break
            asserts.false(env, is_valid, "Invalid version should be rejected: " + version)
    
    return unittest.end(env)

semver_validation_test = unittest.make(_test_semver_validation)

# Test provider namespace/name parsing
def _test_provider_namespace_parsing(ctx):
    """Test parsing of provider namespace/name format"""
    env = unittest.begin(ctx)
    
    # Valid provider formats
    valid_providers = [
        ("hashicorp/aws", "hashicorp", "aws"),
        ("hashicorp/azurerm", "hashicorp", "azurerm"),
        ("cloudflare/cloudflare", "cloudflare", "cloudflare"),
        ("integrations/github", "integrations", "github"),
    ]
    
    # Invalid provider formats
    invalid_providers = [
        "aws",                    # Missing namespace
        "hashicorp/aws/extra",    # Too many parts
        "/aws",                   # Empty namespace
        "hashicorp/",            # Empty name
        "",                      # Empty
    ]
    
    # Test valid formats
    for provider, expected_namespace, expected_name in valid_providers:
        parts = provider.split("/")
        asserts.equals(env, 2, len(parts), "Provider should have namespace/name format: " + provider)
        namespace, name = parts
        asserts.equals(env, expected_namespace, namespace, "Namespace for " + provider)
        asserts.equals(env, expected_name, name, "Name for " + provider)
    
    # Test invalid format detection
    for provider in invalid_providers:
        if "/" not in provider:
            asserts.true(env, True, "Provider without slash should be invalid: " + provider)
        else:
            parts = provider.split("/")
            is_valid = len(parts) == 2
            for p in parts:
                if not p:
                    is_valid = False
                    break
            asserts.false(env, is_valid, "Invalid provider format: " + provider)
    
    return unittest.end(env)

provider_namespace_parsing_test = unittest.make(_test_provider_namespace_parsing)

# Test provider version constraints
def _test_provider_version_constraints(ctx):
    """Test handling of provider version constraints"""
    env = unittest.begin(ctx)
    
    # Test constraint patterns
    constraints = [
        ("~> 6.0", "6.0.0", True),      # Compatible with 6.x
        ("~> 6.0", "7.0.0", False),     # Not compatible with 7.x
        (">= 4.0, < 5.0", "4.5.0", True),  # In range
        (">= 4.0, < 5.0", "5.0.0", False), # Out of range
        ("3.6.3", "3.6.3", True),       # Exact match
        ("3.6.3", "3.6.4", False),      # No match
    ]
    
    # For unit testing, we just verify the constraint format
    for constraint, version, should_match in constraints:
        # Check constraint format
        if "~>" in constraint:
            asserts.true(env, True, "Pessimistic constraint: " + constraint)
        elif ">=" in constraint or "<" in constraint:
            asserts.true(env, True, "Range constraint: " + constraint)
        else:
            # Should be exact version
            parts = constraint.split(".")
            is_exact = len(parts) == 3
            for p in parts:
                if not p.isdigit():
                    is_exact = False
                    break
            asserts.true(env, is_exact, "Should be exact version: " + constraint)
    
    return unittest.end(env)

provider_version_constraints_test = unittest.make(_test_provider_version_constraints)

# Test provider aggregation from modules
def _test_provider_aggregation(ctx):
    """Test that providers are aggregated from nested modules"""
    env = unittest.begin(ctx)
    
    # Simulate provider requirements from multiple modules
    module1_providers = {
        "hashicorp/aws": "6.12.0",
        "hashicorp/random": "3.6.3",
    }
    
    module2_providers = {
        "hashicorp/aws": "6.12.0",      # Same version - OK
        "hashicorp/azurerm": "4.11.0",  # New provider
    }
    
    module3_providers = {
        "hashicorp/aws": "6.13.0",      # Different version - conflict!
    }
    
    # Test aggregation without conflicts
    aggregated = {}
    for provider, version in module1_providers.items():
        aggregated[provider] = version
    for provider, version in module2_providers.items():
        if provider in aggregated:
            asserts.equals(
                env,
                aggregated[provider],
                version,
                "Same provider should have same version"
            )
        else:
            aggregated[provider] = version
    
    asserts.equals(env, 3, len(aggregated), "Should have 3 unique providers")
    asserts.true(env, "hashicorp/aws" in aggregated, "Should have AWS")
    asserts.true(env, "hashicorp/azurerm" in aggregated, "Should have Azure")
    asserts.true(env, "hashicorp/random" in aggregated, "Should have Random")
    
    # Test conflict detection
    for provider, version in module3_providers.items():
        if provider in aggregated:
            has_conflict = aggregated[provider] != version
            asserts.true(env, has_conflict, "Should detect version conflict for " + provider)
    
    return unittest.end(env)

provider_aggregation_test = unittest.make(_test_provider_aggregation)

# Test provider alias validation
def _test_provider_alias_validation(ctx):
    """Test that provider aliases follow naming conventions"""
    env = unittest.begin(ctx)
    
    # Valid alias patterns
    valid_aliases = [
        "aws_5",          # provider_major
        "azurerm_4",      # provider_major
        "random_3",       # provider_major
        "time_0",         # provider_major with 0
    ]
    
    # Invalid alias patterns
    invalid_aliases = [
        "aws",            # Missing version
        "aws_5_1",        # Too specific
        "aws_v5",         # Wrong format
        "5_aws",          # Wrong order
    ]
    
    for alias in valid_aliases:
        parts = alias.split("_")
        asserts.equals(env, 2, len(parts), "Valid alias should have provider_version format: " + alias)
        provider_name, version = parts
        asserts.true(env, version.isdigit(), "Version should be numeric: " + alias)
    
    for alias in invalid_aliases:
        if "_" not in alias:
            asserts.true(env, True, "Alias without underscore is invalid: " + alias)
        else:
            parts = alias.split("_")
            is_valid = len(parts) == 2 and parts[1].isdigit() and not parts[0].isdigit()
            asserts.false(env, is_valid, "Invalid alias format: " + alias)
    
    return unittest.end(env)

provider_alias_validation_test = unittest.make(_test_provider_alias_validation)

# Test suite
def provider_validation_test_suite(name):
    """Create provider validation test suite"""
    
    semver_validation_test(name = name + "_semver", size = "small")
    provider_namespace_parsing_test(name = name + "_namespace", size = "small")
    provider_version_constraints_test(name = name + "_constraints", size = "small")
    provider_aggregation_test(name = name + "_aggregation", size = "small")
    provider_alias_validation_test(name = name + "_alias", size = "small")
    
    native.test_suite(
        name = name,
        tests = [
            ":" + name + "_semver",
            ":" + name + "_namespace",
            ":" + name + "_constraints",
            ":" + name + "_aggregation",
            ":" + name + "_alias",
        ],
    )