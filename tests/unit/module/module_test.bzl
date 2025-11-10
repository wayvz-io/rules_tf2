"""Unit tests for Terraform module rules"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tf2/module/core:tf_module.bzl", "tf_module_deps", "tf_module_rule")
load("//tf2/providers/core:info.bzl", "TfModuleInfo", "TfProviderConfigurationsInfo")

# Test that tf_module_rule creates proper providers
def _tf_module_basic_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that TfModuleInfo provider is created
    asserts.true(
        env,
        TfModuleInfo in target_under_test,
        "tf_module_rule should provide TfModuleInfo",
    )

    # Check module info fields
    module_info = target_under_test[TfModuleInfo]
    asserts.equals(
        env,
        "test_module",
        module_info.name,
        "Module name should match label name",
    )

    # Check that srcs is a depset
    asserts.true(
        env,
        type(module_info.srcs) == "depset",
        "srcs should be a depset",
    )

    return analysistest.end(env)

tf_module_basic_test = analysistest.make(_tf_module_basic_test_impl)

# Test tf_module_deps aggregates dependencies correctly
def _tf_module_deps_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that DefaultInfo is provided
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_module_deps should provide DefaultInfo",
    )

    # Check that files are aggregated
    default_info = target_under_test[DefaultInfo]
    files = default_info.files.to_list()

    # We expect files from both dependencies
    asserts.true(
        env,
        len(files) > 0,
        "tf_module_deps should aggregate files from dependencies",
    )

    return analysistest.end(env)

tf_module_deps_test = analysistest.make(_tf_module_deps_test_impl)

# Test that nested modules are processed correctly
# Commented out due to file generation conflicts with nested modules
# def _tf_module_nested_test_impl(ctx):
#     env = analysistest.begin(ctx)
#
#     target_under_test = analysistest.target_under_test(env)
#     module_info = target_under_test[TfModuleInfo]
#
#     # Check that modules list is populated
#     asserts.true(
#         env,
#         len(module_info.modules) > 0,
#         "Nested modules should be included in module info"
#     )
#
#     return analysistest.end(env)
#
# tf_module_nested_test = analysistest.make(_tf_module_nested_test_impl)

# Test empty module (no srcs)
def _tf_module_empty_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    module_info = target_under_test[TfModuleInfo]

    # Check that empty module still provides TfModuleInfo
    asserts.true(
        env,
        TfModuleInfo in target_under_test,
        "Empty module should still provide TfModuleInfo",
    )

    # Check that srcs is an empty depset
    srcs_list = module_info.srcs.to_list()
    asserts.equals(
        env,
        0,
        len(srcs_list),
        "Empty module should have no sources",
    )

    return analysistest.end(env)

tf_module_empty_test = analysistest.make(_tf_module_empty_test_impl)

# Test module with provider configurations
def _tf_module_with_providers_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    module_info = target_under_test[TfModuleInfo]

    # Check that provider_configurations is set
    asserts.true(
        env,
        module_info.provider_configurations != None,
        "Module should have provider configurations",
    )

    return analysistest.end(env)

tf_module_with_providers_test = analysistest.make(_tf_module_with_providers_test_impl)

# Helper rules to create test targets
def _test_module_impl(ctx):
    """Simple module implementation for testing"""
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        TfModuleInfo(
            name = ctx.label.name,
            srcs = depset(ctx.files.srcs),
            deps = [],
            modules = ctx.attr.modules if hasattr(ctx.attr, "modules") else [],
            provider_configurations = ctx.attr.provider_configurations if hasattr(ctx.attr, "provider_configurations") else None,
        ),
    ]

test_module_rule = rule(
    implementation = _test_module_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "modules": attr.label_list(),
        "provider_configurations": attr.label(),
    },
)

def _test_provider_config_impl(_):
    """Simple provider configuration for testing"""
    return [
        DefaultInfo(files = depset()),
        TfProviderConfigurationsInfo(
            providers = {"aws": "6.12.0", "azurerm": "4.11.0"},
        ),
    ]

test_provider_config_rule = rule(
    implementation = _test_provider_config_impl,
)

# Test suite setup
def module_test_suite(name):
    """Create all module test targets

    Args:
        name: Name of the test suite
    """

    # Create test data files with unique names
    native.genrule(
        name = name + "_main_tf",
        outs = [name + "_main.tf"],
        cmd = "echo 'resource \"aws_instance\" \"test\" {}' > $@",
    )

    native.genrule(
        name = name + "_variables_tf",
        outs = [name + "_variables.tf"],
        cmd = "echo 'variable \"test\" {}' > $@",
    )

    # Create a test provider configuration
    test_provider_config_rule(
        name = "test_provider_config",
    )

    # Test basic module
    tf_module_rule(
        name = "test_module",
        srcs = [":" + name + "_main.tf", ":" + name + "_variables.tf"],
        provider_configurations = ":test_provider_config",
    )

    tf_module_basic_test(
        name = "tf_module_basic_test",
        target_under_test = ":test_module",
        size = "small",
    )

    # Test module dependencies
    test_module_rule(
        name = "dep_module_1",
        srcs = [":" + name + "_main.tf"],
    )

    test_module_rule(
        name = "dep_module_2",
        srcs = [":" + name + "_variables.tf"],
    )

    tf_module_deps(
        name = "test_module_deps",
        deps = [":dep_module_1", ":dep_module_2"],
    )

    tf_module_deps_test(
        name = "tf_module_deps_test",
        target_under_test = ":test_module_deps",
        size = "small",
    )

    # Test empty module
    tf_module_rule(
        name = "test_empty_module",
        srcs = [],
        provider_configurations = ":test_provider_config",
    )

    tf_module_empty_test(
        name = "tf_module_empty_test",
        target_under_test = ":test_empty_module",
        size = "small",
    )

    # Test module with providers
    tf_module_rule(
        name = "test_module_with_providers",
        srcs = [":" + name + "_main.tf"],
        provider_configurations = ":test_provider_config",
    )

    tf_module_with_providers_test(
        name = "tf_module_with_providers_test",
        target_under_test = ":test_module_with_providers",
        size = "small",
    )

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_module_basic_test",
            ":tf_module_deps_test",
            # ":tf_module_nested_test",  # Removed due to file generation conflicts
            ":tf_module_empty_test",
            ":tf_module_with_providers_test",
        ],
    )
