"""Unit tests for module_aliases functionality in stack module staging."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/tfstack:nested.bzl", "derive_component_name")

def _mock_label(package, name):
    """Create a mock label struct for testing."""
    return struct(
        package = package,
        name = name,
    )

def _test_derive_component_name_no_alias_generic_name_impl(ctx):
    """Test deriving component name without alias, with generic target name."""
    env = unittest.begin(ctx)

    label = _mock_label("iac/networking/aws/environment_workloads", "tf_module")
    result = derive_component_name(label, {})

    asserts.equals(env, "environment_workloads", result, "Should use package name for generic target")

    return unittest.end(env)

derive_component_name_no_alias_generic_name_test = unittest.make(_test_derive_component_name_no_alias_generic_name_impl)

def _test_derive_component_name_no_alias_custom_name_impl(ctx):
    """Test deriving component name without alias, with custom target name."""
    env = unittest.begin(ctx)

    label = _mock_label("iac/networking/aws/environment_workloads", "my_custom_module")
    result = derive_component_name(label, {})

    asserts.equals(env, "my_custom_module", result, "Should use target name for non-generic target")

    return unittest.end(env)

derive_component_name_no_alias_custom_name_test = unittest.make(_test_derive_component_name_no_alias_custom_name_impl)

def _test_derive_component_name_with_alias_impl(ctx):
    """Test deriving component name with explicit alias using //package:name format."""
    env = unittest.begin(ctx)

    label = _mock_label("iac/networking/aws/environment_workloads", "tf_module")
    aliases = {
        "//iac/networking/aws/environment_workloads:tf_module": "aws_environment_workloads",
    }
    result = derive_component_name(label, aliases)

    asserts.equals(env, "aws_environment_workloads", result, "Should use explicit alias")

    return unittest.end(env)

derive_component_name_with_alias_test = unittest.make(_test_derive_component_name_with_alias_impl)

def _test_derive_component_name_alias_overrides_custom_name_impl(ctx):
    """Test that alias overrides even a custom (non-generic) target name."""
    env = unittest.begin(ctx)

    # Even though the target has a custom name, the alias should override it
    label = _mock_label("iac/networking/aws/environment_workloads", "my_custom_module")
    aliases = {
        "//iac/networking/aws/environment_workloads:my_custom_module": "aliased_name",
    }
    result = derive_component_name(label, aliases)

    asserts.equals(env, "aliased_name", result, "Alias should override custom target name")

    return unittest.end(env)

derive_component_name_alias_overrides_custom_name_test = unittest.make(_test_derive_component_name_alias_overrides_custom_name_impl)

def _test_derive_component_name_alias_not_matched_impl(ctx):
    """Test deriving component name when alias doesn't match."""
    env = unittest.begin(ctx)

    label = _mock_label("iac/networking/aws/environment_workloads", "tf_module")
    aliases = {
        "//iac/networking/azure/environment_workloads:tf_module": "azure_workloads",
    }
    result = derive_component_name(label, aliases)

    # Should fall back to default behavior since alias doesn't match
    asserts.equals(env, "environment_workloads", result, "Should fall back to package name when alias doesn't match")

    return unittest.end(env)

derive_component_name_alias_not_matched_test = unittest.make(_test_derive_component_name_alias_not_matched_impl)

def _test_derive_component_name_module_generic_name_impl(ctx):
    """Test deriving component name with 'module' as generic name."""
    env = unittest.begin(ctx)

    label = _mock_label("iac/networking/vpc", "module")
    result = derive_component_name(label, {})

    asserts.equals(env, "vpc", result, "Should use package name for 'module' target")

    return unittest.end(env)

derive_component_name_module_generic_name_test = unittest.make(_test_derive_component_name_module_generic_name_impl)

def module_aliases_test_suite(name):
    """Create all module_aliases test targets.

    Args:
        name: Name of the test suite
    """
    derive_component_name_no_alias_generic_name_test(name = "derive_component_name_no_alias_generic_name_test")
    derive_component_name_no_alias_custom_name_test(name = "derive_component_name_no_alias_custom_name_test")
    derive_component_name_with_alias_test(name = "derive_component_name_with_alias_test")
    derive_component_name_alias_overrides_custom_name_test(name = "derive_component_name_alias_overrides_custom_name_test")
    derive_component_name_alias_not_matched_test(name = "derive_component_name_alias_not_matched_test")
    derive_component_name_module_generic_name_test(name = "derive_component_name_module_generic_name_test")

    native.test_suite(
        name = name,
        tests = [
            ":derive_component_name_no_alias_generic_name_test",
            ":derive_component_name_no_alias_custom_name_test",
            ":derive_component_name_with_alias_test",
            ":derive_component_name_alias_overrides_custom_name_test",
            ":derive_component_name_alias_not_matched_test",
            ":derive_component_name_module_generic_name_test",
        ],
    )
