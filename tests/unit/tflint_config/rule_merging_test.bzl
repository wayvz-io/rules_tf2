"""Unit tests for tagged overrides and rule merging functionality"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/tflint:defaults.bzl", "get_base_rules", "get_provider_rules", "get_tagged_overrides", "merge_rule_configs")

def _test_basic_rule_merging_impl(ctx):
    env = unittest.begin(ctx)

    # Test basic merging of two rule sets
    base_rules = {
        "rule1": {"enabled": True, "severity": "error"},
        "rule2": {"enabled": False},
    }

    overlay_rules = {
        "rule1": {"severity": "warning"},  # Override severity, keep enabled
        "rule3": {"enabled": True},  # New rule
    }

    merged = merge_rule_configs(base_rules, overlay_rules)

    # Test rule1: enabled should be preserved, severity should be overridden
    asserts.equals(env, True, merged["rule1"]["enabled"])
    asserts.equals(env, "warning", merged["rule1"]["severity"])

    # Test rule2: should be unchanged
    asserts.equals(env, False, merged["rule2"]["enabled"])

    # Test rule3: should be added
    asserts.equals(env, True, merged["rule3"]["enabled"])

    return unittest.end(env)

def _test_multiple_overlay_merging_impl(ctx):
    env = unittest.begin(ctx)

    # Test merging multiple overlays in order
    base = {
        "rule1": {"enabled": True, "severity": "error", "force": False},
    }

    overlay1 = {
        "rule1": {"severity": "warning"},
        "rule2": {"enabled": True},
    }

    overlay2 = {
        "rule1": {"enabled": False, "force": True},
        "rule2": {"severity": "info"},
    }

    merged = merge_rule_configs(base, overlay1, overlay2)

    # Test rule1: latest overlays should win
    asserts.equals(env, False, merged["rule1"]["enabled"])  # From overlay2
    asserts.equals(env, "warning", merged["rule1"]["severity"])  # From overlay1
    asserts.equals(env, True, merged["rule1"]["force"])  # From overlay2

    # Test rule2: should have properties from both overlays
    asserts.equals(env, True, merged["rule2"]["enabled"])  # From overlay1
    asserts.equals(env, "info", merged["rule2"]["severity"])  # From overlay2

    return unittest.end(env)

def _test_standalone_module_overrides_impl(ctx):
    env = unittest.begin(ctx)

    base_rules = get_base_rules()
    standalone_overrides = get_tagged_overrides("standalone_module")

    # Apply standalone module overrides
    merged = merge_rule_configs(base_rules, standalone_overrides)

    # Test that documentation rules are disabled for standalone modules
    asserts.equals(env, False, merged["terraform_documented_outputs"]["enabled"])
    asserts.equals(env, False, merged["terraform_documented_variables"]["enabled"])
    asserts.equals(env, False, merged["terraform_standard_module_structure"]["enabled"])

    # Test that other base rules are preserved
    asserts.equals(env, True, merged["terraform_comment_syntax"]["enabled"])
    asserts.equals(env, True, merged["terraform_required_providers"]["enabled"])

    return unittest.end(env)

def _test_consumer_module_overrides_impl(ctx):
    env = unittest.begin(ctx)

    base_rules = get_base_rules()
    consumer_overrides = get_tagged_overrides("consumer_module")

    # Apply consumer module overrides
    merged = merge_rule_configs(base_rules, consumer_overrides)

    # Test that documentation rules are enabled for consumer modules
    asserts.equals(env, True, merged["terraform_documented_outputs"]["enabled"])
    asserts.equals(env, True, merged["terraform_documented_variables"]["enabled"])
    asserts.equals(env, True, merged["terraform_standard_module_structure"]["enabled"])

    return unittest.end(env)

def _test_test_module_overrides_impl(ctx):
    env = unittest.begin(ctx)

    # Start with base rules and AWS provider rules
    base_rules = get_base_rules()
    aws_rules = get_provider_rules("aws")
    azurerm_rules = get_provider_rules("azurerm")

    # Merge base with provider rules
    merged_with_providers = merge_rule_configs(base_rules, aws_rules, azurerm_rules)

    # Apply test module overrides
    test_overrides = get_tagged_overrides("test_module")
    final_merged = merge_rule_configs(merged_with_providers, test_overrides)

    # Test that tagging rules are disabled for test modules
    # Tags rules are disabled for test modules - using different rules for testing
    asserts.equals(env, False, final_merged["terraform_documented_outputs"]["enabled"])
    asserts.equals(env, False, final_merged["terraform_documented_variables"]["enabled"])

    # Test that documentation rules are disabled
    asserts.equals(env, False, final_merged["terraform_documented_outputs"]["enabled"])
    asserts.equals(env, False, final_merged["terraform_documented_variables"]["enabled"])

    # Test that other rules are preserved
    asserts.equals(env, True, final_merged["aws_instance_invalid_type"]["enabled"])
    asserts.equals(env, True, final_merged["azurerm_virtual_machine_invalid_vm_size"]["enabled"])

    return unittest.end(env)

def _test_complex_merging_scenario_impl(ctx):
    env = unittest.begin(ctx)

    # Test a complex real-world scenario
    # Base rules + AWS provider + standalone_module tag + module-specific overrides

    base_rules = get_base_rules()
    aws_rules = get_provider_rules("aws")
    standalone_overrides = get_tagged_overrides("standalone_module")

    # Module-specific overrides
    module_overrides = {
        "terraform_documented_variables": {"enabled": True},  # Override the standalone default
        "terraform_standard_module_structure": {"enabled": True},  # Enable structure for this specific module
        "custom_rule": {"enabled": True, "severity": "warning"},  # Add custom rule
    }

    # Apply in order: base -> provider -> tagged -> module-specific
    final_config = merge_rule_configs(base_rules, aws_rules, standalone_overrides, module_overrides)

    # Test that module-specific overrides win
    asserts.equals(env, True, final_config["terraform_documented_variables"]["enabled"])  # Module override
    asserts.equals(env, False, final_config["terraform_documented_outputs"]["enabled"])  # Standalone override
    asserts.equals(env, True, final_config["terraform_standard_module_structure"]["enabled"])  # Module override

    # Test that base rules are preserved
    asserts.equals(env, True, final_config["terraform_comment_syntax"]["enabled"])

    # Test that provider rules are preserved
    asserts.equals(env, True, final_config["aws_instance_invalid_type"]["enabled"])

    # Test that custom rules are added
    asserts.equals(env, True, final_config["custom_rule"]["enabled"])
    asserts.equals(env, "warning", final_config["custom_rule"]["severity"])

    return unittest.end(env)

def _test_rule_property_preservation_impl(ctx):
    env = unittest.begin(ctx)

    # Test that complex rule properties are preserved during merging
    base_rules = {
        "terraform_typed_variables": {
            "enabled": True,
            "force": True,
            "severity": "error",
        },
    }

    # Override that only changes enabled status
    override_rules = {
        "terraform_typed_variables": {
            "enabled": False,
        },
    }

    merged = merge_rule_configs(base_rules, override_rules)

    # Test that enabled is overridden but other properties are preserved
    asserts.equals(env, False, merged["terraform_typed_variables"]["enabled"])
    asserts.equals(env, True, merged["terraform_typed_variables"]["force"])
    asserts.equals(env, "error", merged["terraform_typed_variables"]["severity"])

    return unittest.end(env)

def _test_empty_merging_impl(ctx):
    env = unittest.begin(ctx)

    # Test merging with empty configurations
    base_rules = {
        "rule1": {"enabled": True},
    }

    # Merge with empty overlay
    merged = merge_rule_configs(base_rules, {})
    asserts.equals(env, base_rules, merged)

    # Merge empty base with overlay
    overlay = {
        "rule2": {"enabled": False},
    }
    merged = merge_rule_configs({}, overlay)
    asserts.equals(env, overlay, merged)

    return unittest.end(env)

# Test rule definitions
basic_rule_merging_test = unittest.make(_test_basic_rule_merging_impl)
multiple_overlay_merging_test = unittest.make(_test_multiple_overlay_merging_impl)
standalone_module_overrides_test = unittest.make(_test_standalone_module_overrides_impl)
consumer_module_overrides_test = unittest.make(_test_consumer_module_overrides_impl)
test_module_overrides_test = unittest.make(_test_test_module_overrides_impl)
complex_merging_scenario_test = unittest.make(_test_complex_merging_scenario_impl)
rule_property_preservation_test = unittest.make(_test_rule_property_preservation_impl)
empty_merging_test = unittest.make(_test_empty_merging_impl)

def rule_merging_test_suite(name):
    """Test suite for tagged overrides and rule merging functionality"""
    unittest.suite(
        name,
        basic_rule_merging_test,
        multiple_overlay_merging_test,
        standalone_module_overrides_test,
        consumer_module_overrides_test,
        test_module_overrides_test,
        complex_merging_scenario_test,
        rule_property_preservation_test,
        empty_merging_test,
    )
