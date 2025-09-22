"""Unit tests for versions.json parser functions"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//tf2/providers/repository:versions.bzl",
    "get_providers",
    "get_tflint_config",
    "get_tflint_plugin_version",
    "get_tool_version",
)

def _test_get_tool_version_impl(ctx):
    env = unittest.begin(ctx)

    # Test data
    versions_data = {
        "tools": {
            "terraform": "1.13.2",
            "tflint": "0.59.1",
            "terraform-docs": "0.20.0",
        },
    }

    # Test getting existing tool versions
    asserts.equals(env, "1.13.2", get_tool_version(versions_data, "terraform"))
    asserts.equals(env, "0.59.1", get_tool_version(versions_data, "tflint"))
    asserts.equals(env, "0.20.0", get_tool_version(versions_data, "terraform-docs"))

    # Test getting non-existent tool with default
    asserts.equals(env, "1.0.0", get_tool_version(versions_data, "nonexistent", "1.0.0"))
    asserts.equals(env, None, get_tool_version(versions_data, "nonexistent"))

    # Test with missing tools section
    empty_data = {}
    asserts.equals(env, "default", get_tool_version(empty_data, "terraform", "default"))

    return unittest.end(env)

def _test_get_tflint_plugin_version_impl(ctx):
    env = unittest.begin(ctx)

    # Test data
    versions_data = {
        "tflint_plugins": {
            "aws": "0.42.0",
            "azurerm": "0.29.0",
            "google": "0.35.0",
            "opa": "0.9.0",
        },
    }

    # Test getting existing plugin versions
    asserts.equals(env, "0.42.0", get_tflint_plugin_version(versions_data, "aws"))
    asserts.equals(env, "0.29.0", get_tflint_plugin_version(versions_data, "azurerm"))
    asserts.equals(env, "0.35.0", get_tflint_plugin_version(versions_data, "google"))
    asserts.equals(env, "0.9.0", get_tflint_plugin_version(versions_data, "opa"))

    # Test getting non-existent plugin
    asserts.equals(env, None, get_tflint_plugin_version(versions_data, "nonexistent"))

    # Test with missing plugins section
    empty_data = {}
    asserts.equals(env, None, get_tflint_plugin_version(empty_data, "aws"))

    return unittest.end(env)

def _test_get_tflint_config_impl(ctx):
    env = unittest.begin(ctx)

    # Test data with partial config
    versions_data = {
        "tflint_config": {
            "global": {
                "format": "json",
                "force": True,
            },
            "rules": {
                "terraform": {
                    "terraform_naming_convention": {"enabled": False},
                },
            },
        },
    }

    config = get_tflint_config(versions_data)

    # Test that global config is returned correctly
    asserts.equals(env, "json", config["global"]["format"])
    asserts.equals(env, True, config["global"]["force"])
    asserts.equals(env, False, config["global"]["disabled_by_default"])  # Default value

    # Test that rules are returned correctly
    asserts.equals(env, False, config["rules"]["terraform"]["terraform_naming_convention"]["enabled"])

    # Test that tagged_overrides defaults to empty dict
    asserts.equals(env, {}, config["tagged_overrides"])

    # Test with completely missing tflint_config
    empty_data = {}
    config = get_tflint_config(empty_data)

    # Should return defaults
    asserts.equals(env, "compact", config["global"]["format"])
    asserts.equals(env, False, config["global"]["force"])
    asserts.equals(env, False, config["global"]["disabled_by_default"])
    asserts.equals(env, {}, config["rules"])
    asserts.equals(env, {}, config["tagged_overrides"])

    return unittest.end(env)

def _test_get_providers_impl(ctx):
    env = unittest.begin(ctx)

    # Test data
    versions_data = {
        "providers": {
            "hashicorp/aws": ["6.13.0", "5.100.0"],
            "hashicorp/azurerm": ["4.44.0"],
            "paloaltonetworks/panos": ["2.0.5"],
        },
    }

    providers = get_providers(versions_data)

    # Test that providers are returned correctly
    asserts.equals(env, ["6.13.0", "5.100.0"], providers["hashicorp/aws"])
    asserts.equals(env, ["4.44.0"], providers["hashicorp/azurerm"])
    asserts.equals(env, ["2.0.5"], providers["paloaltonetworks/panos"])

    # Test with missing providers section
    empty_data = {}
    providers = get_providers(empty_data)
    asserts.equals(env, {}, providers)

    return unittest.end(env)

# Test rule definitions
get_tool_version_test = unittest.make(_test_get_tool_version_impl)
get_tflint_plugin_version_test = unittest.make(_test_get_tflint_plugin_version_impl)
get_tflint_config_test = unittest.make(_test_get_tflint_config_impl)
get_providers_test = unittest.make(_test_get_providers_impl)

def versions_parser_test_suite(name):
    """Test suite for versions.json parser functions"""
    unittest.suite(
        name,
        get_tool_version_test,
        get_tflint_plugin_version_test,
        get_tflint_config_test,
        get_providers_test,
    )
