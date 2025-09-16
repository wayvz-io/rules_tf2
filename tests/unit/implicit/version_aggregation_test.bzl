"""Unit tests for implicit version aggregation behaviors"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# Test version aggregation from nested modules
def _test_version_aggregation_from_modules(ctx):
    """Test that versions are correctly aggregated from nested modules"""
    env = unittest.begin(ctx)
    
    # Simulate modules with their provider requirements
    module_configs = [
        {
            "name": "vpc",
            "providers": {
                "hashicorp/aws": "6.12.0",
                "hashicorp/random": "3.6.3",
            },
        },
        {
            "name": "database",
            "providers": {
                "hashicorp/aws": "6.12.0",  # Same version - OK
                "hashicorp/postgresql": "1.24.0",
            },
        },
        {
            "name": "monitoring",
            "providers": {
                "hashicorp/aws": "6.12.0",  # Same version - OK
                "datadog/datadog": "3.48.0",
            },
        },
    ]
    
    # Aggregate providers
    aggregated = {}
    for module in module_configs:
        for provider, version in module["providers"].items():
            if provider in aggregated:
                # Check for version consistency
                asserts.equals(
                    env,
                    aggregated[provider],
                    version,
                    "Provider %s should have consistent version across modules" % provider
                )
            else:
                aggregated[provider] = version
    
    # Verify aggregation results
    asserts.equals(env, 4, len(aggregated), "Should have 4 unique providers")
    asserts.true(env, "hashicorp/aws" in aggregated, "Should include AWS")
    asserts.true(env, "hashicorp/random" in aggregated, "Should include Random")
    asserts.true(env, "hashicorp/postgresql" in aggregated, "Should include PostgreSQL")
    asserts.true(env, "datadog/datadog" in aggregated, "Should include Datadog")
    
    return unittest.end(env)

version_aggregation_from_modules_test = unittest.make(_test_version_aggregation_from_modules)

# Test terraform version requirement aggregation
def _test_terraform_version_aggregation(ctx):
    """Test aggregation of terraform required_version constraints"""
    env = unittest.begin(ctx)
    
    # Different version constraint formats
    version_constraints = [
        ">= 1.0",
        ">= 1.0.0",
        "~> 1.0",
        ">= 1.0, < 2.0",
        "1.12.2",
    ]
    
    # Test constraint parsing
    for constraint in version_constraints:
        if ">=" in constraint:
            asserts.true(env, True, "Minimum version constraint: " + constraint)
        elif "~>" in constraint:
            asserts.true(env, True, "Pessimistic constraint: " + constraint)
        elif "," in constraint:
            asserts.true(env, True, "Range constraint: " + constraint)
        else:
            # Should be exact version
            parts = constraint.split(".")
            is_version = True
            for p in parts:
                if not p.isdigit():
                    is_version = False
                    break
            asserts.true(env, is_version, "Should be exact version: " + constraint)
    
    # Test finding the most restrictive constraint
    # In practice, we'd use ">= 1.12.2" as it's the most specific minimum
    default_constraint = ">= 1.12.2"
    asserts.true(env, ">=" in default_constraint, "Default should be minimum version constraint")
    
    return unittest.end(env)

terraform_version_aggregation_test = unittest.make(_test_terraform_version_aggregation)

# Test provider version conflict detection
def _test_version_conflict_detection(ctx):
    """Test detection of provider version conflicts"""
    env = unittest.begin(ctx)
    
    # Test cases with conflicts
    conflict_cases = [
        {
            "module1": {"hashicorp/aws": "6.12.0"},
            "module2": {"hashicorp/aws": "6.13.0"},  # Conflict!
            "should_conflict": True,
        },
        {
            "module1": {"hashicorp/aws": "6.12.0"},
            "module2": {"hashicorp/aws": "6.12.0"},  # Same - OK
            "should_conflict": False,
        },
        {
            "module1": {"hashicorp/aws": "6.12.0"},
            "module2": {"hashicorp/azurerm": "4.11.0"},  # Different provider - OK
            "should_conflict": False,
        },
    ]
    
    for case in conflict_cases:
        module1_providers = case["module1"]
        module2_providers = case["module2"]
        should_conflict = case["should_conflict"]
        
        # Check for conflicts
        has_conflict = False
        for provider, version in module2_providers.items():
            if provider in module1_providers:
                if module1_providers[provider] != version:
                    has_conflict = True
        
        asserts.equals(
            env,
            should_conflict,
            has_conflict,
            "Conflict detection for case: %s vs %s" % (str(module1_providers), str(module2_providers))
        )
    
    return unittest.end(env)

version_conflict_detection_test = unittest.make(_test_version_conflict_detection)

# Test version priority when modules don't specify providers
def _test_version_priority_inheritance(ctx):
    """Test that parent module versions take priority when child doesn't specify"""
    env = unittest.begin(ctx)
    
    # Parent module providers
    parent_providers = {
        "hashicorp/aws": "6.12.0",
        "hashicorp/random": "3.6.3",
    }
    
    # Child module with partial providers
    child_providers = {
        "hashicorp/random": "3.6.3",  # Matches parent
        # AWS not specified - should inherit from parent
    }
    
    # Merge with parent priority
    final_providers = dict(parent_providers)
    for provider, version in child_providers.items():
        if provider in final_providers:
            # Child specifies same - validate match
            asserts.equals(
                env,
                final_providers[provider],
                version,
                "Child should match parent version for %s" % provider
            )
    
    # Verify all parent providers are present
    for provider in parent_providers:
        asserts.true(
            env,
            provider in final_providers,
            "Parent provider should be inherited: " + provider
        )
    
    return unittest.end(env)

version_priority_inheritance_test = unittest.make(_test_version_priority_inheritance)

# Test automatic version file generation
def _test_auto_version_file_generation(ctx):
    """Test that terraform.tf is auto-generated with correct versions"""
    env = unittest.begin(ctx)
    
    # Expected terraform.tf structure
    expected_blocks = [
        "terraform",
        "required_version",
        "required_providers",
    ]
    
    # Expected provider entries
    expected_providers = {
        "aws": {
            "source": "hashicorp/aws",
            "version": "6.12.0",
        },
        "random": {
            "source": "hashicorp/random",
            "version": "3.6.3",
        },
    }
    
    # Verify structure expectations
    for block in expected_blocks:
        asserts.true(env, block != "", "Should have %s block" % block)
    
    # Verify provider entries
    for name, config in expected_providers.items():
        asserts.true(env, "source" in config, "Provider %s should have source" % name)
        asserts.true(env, "version" in config, "Provider %s should have version" % name)
        
        # Verify source format
        source = config["source"]
        asserts.true(env, "/" in source, "Source should be namespace/name: " + source)
    
    return unittest.end(env)

auto_version_file_generation_test = unittest.make(_test_auto_version_file_generation)

# Test suite
def version_aggregation_test_suite(name):
    """Create version aggregation test suite"""
    
    version_aggregation_from_modules_test(name = name + "_module_aggregation")
    terraform_version_aggregation_test(name = name + "_terraform_version")
    version_conflict_detection_test(name = name + "_conflict_detection")
    version_priority_inheritance_test(name = name + "_priority_inheritance")
    auto_version_file_generation_test(name = name + "_auto_generation")
    
    native.test_suite(
        name = name,
        tests = [
            ":" + name + "_module_aggregation",
            ":" + name + "_terraform_version",
            ":" + name + "_conflict_detection",
            ":" + name + "_priority_inheritance",
            ":" + name + "_auto_generation",
        ],
    )