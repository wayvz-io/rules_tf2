"""Unit tests for TFLint default rule configurations"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//tf2/tflint:defaults.bzl",
    "get_base_rules",
    "get_provider_rules",
    "get_tagged_overrides",
    "merge_rule_configs",
)

def _test_get_base_rules_impl(ctx):
    env = unittest.begin(ctx)

    base_rules = get_base_rules()

    # Test that base Terraform rules are present
    asserts.true(env, "terraform_comment_syntax" in base_rules)
    asserts.true(env, "terraform_documented_outputs" in base_rules)
    asserts.true(env, "terraform_required_providers" in base_rules)
    asserts.true(env, "terraform_typed_variables" in base_rules)

    # Test specific rule configurations
    asserts.equals(env, True, base_rules["terraform_comment_syntax"]["enabled"])
    asserts.equals(env, True, base_rules["terraform_documented_outputs"]["enabled"])
    asserts.equals(env, False, base_rules["terraform_standard_module_structure"]["enabled"])
    asserts.equals(env, True, base_rules["terraform_typed_variables"]["force"])

    return unittest.end(env)

def _test_get_provider_rules_impl(ctx):
    env = unittest.begin(ctx)

    # Test AWS provider rules
    aws_rules = get_provider_rules("aws")
    asserts.true(env, "aws_instance_invalid_type" in aws_rules)
    asserts.true(env, "aws_instance_invalid_ami" in aws_rules)
    asserts.equals(env, True, aws_rules["aws_instance_invalid_type"]["enabled"])
    asserts.equals(env, False, aws_rules["aws_instance_invalid_ami_owner"]["enabled"])  # Deep scan disabled

    # Test Azure provider rules
    azurerm_rules = get_provider_rules("azurerm")
    asserts.true(env, "azurerm_virtual_machine_invalid_vm_size" in azurerm_rules)
    asserts.true(env, "azurerm_container_group_invalid_os_type" in azurerm_rules)
    asserts.equals(env, True, azurerm_rules["azurerm_virtual_machine_invalid_vm_size"]["enabled"])
    asserts.equals(env, False, azurerm_rules["azurerm_virtual_machine_invalid_image"]["enabled"])  # Deep scan disabled

    # Test Google provider rules
    google_rules = get_provider_rules("google")
    asserts.true(env, "google_compute_instance_invalid_machine_type" in google_rules)
    asserts.equals(env, True, google_rules["google_compute_instance_invalid_machine_type"]["enabled"])

    # Test OPA provider rules
    opa_rules = get_provider_rules("opa")
    asserts.true(env, "opa_policy" in opa_rules)
    asserts.equals(env, True, opa_rules["opa_policy"]["enabled"])

    # Test non-existent provider
    unknown_rules = get_provider_rules("nonexistent")
    asserts.equals(env, {}, unknown_rules)

    return unittest.end(env)

def _test_get_tagged_overrides_impl(ctx):
    env = unittest.begin(ctx)

    # Test standalone_module overrides
    standalone_overrides = get_tagged_overrides("standalone_module")
    asserts.true(env, "terraform_documented_outputs" in standalone_overrides)
    asserts.true(env, "terraform_documented_variables" in standalone_overrides)
    asserts.equals(env, False, standalone_overrides["terraform_documented_outputs"]["enabled"])
    asserts.equals(env, False, standalone_overrides["terraform_documented_variables"]["enabled"])

    # Test consumer_module overrides
    consumer_overrides = get_tagged_overrides("consumer_module")
    asserts.true(env, "terraform_documented_outputs" in consumer_overrides)
    asserts.true(env, "terraform_standard_module_structure" in consumer_overrides)
    asserts.equals(env, True, consumer_overrides["terraform_documented_outputs"]["enabled"])
    asserts.equals(env, True, consumer_overrides["terraform_standard_module_structure"]["enabled"])

    # Test test_module overrides
    test_overrides = get_tagged_overrides("test_module")
    asserts.true(env, "terraform_documented_outputs" in test_overrides)
    asserts.true(env, "terraform_documented_variables" in test_overrides)
    asserts.equals(env, False, test_overrides["terraform_documented_outputs"]["enabled"])
    asserts.equals(env, False, test_overrides["terraform_documented_variables"]["enabled"])

    # Test non-existent tag
    unknown_overrides = get_tagged_overrides("nonexistent")
    asserts.equals(env, {}, unknown_overrides)

    return unittest.end(env)

def _test_merge_rule_configs_impl(ctx):
    env = unittest.begin(ctx)

    # Test merging configurations
    base = {
        "rule1": {"enabled": True, "severity": "error"},
        "rule2": {"enabled": False},
    }

    overlay1 = {
        "rule1": {"severity": "warning"},  # Override severity, keep enabled
        "rule3": {"enabled": True},  # New rule
    }

    overlay2 = {
        "rule1": {"enabled": False},  # Override enabled
        "rule2": {"force": True},  # Add new property
    }

    merged = merge_rule_configs(base, overlay1, overlay2)

    # Test rule1: should have enabled=False (from overlay2), severity=warning (from overlay1)
    asserts.equals(env, False, merged["rule1"]["enabled"])
    asserts.equals(env, "warning", merged["rule1"]["severity"])

    # Test rule2: should have enabled=False (from base), force=True (from overlay2)
    asserts.equals(env, False, merged["rule2"]["enabled"])
    asserts.equals(env, True, merged["rule2"]["force"])

    # Test rule3: should exist from overlay1
    asserts.equals(env, True, merged["rule3"]["enabled"])

    # Test merging with empty overlays
    same = merge_rule_configs(base)
    asserts.equals(env, base, same)

    return unittest.end(env)

# Test rule definitions
get_base_rules_test = unittest.make(_test_get_base_rules_impl)
get_provider_rules_test = unittest.make(_test_get_provider_rules_impl)
get_tagged_overrides_test = unittest.make(_test_get_tagged_overrides_impl)
merge_rule_configs_test = unittest.make(_test_merge_rule_configs_impl)

def defaults_test_suite(name):
    """Test suite for TFLint default rule configurations"""
    unittest.suite(
        name,
        get_base_rules_test,
        get_provider_rules_test,
        get_tagged_overrides_test,
        merge_rule_configs_test,
    )
