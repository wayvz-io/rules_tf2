"""Unit tests for Terraform provider rules"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest", "unittest")
load("//tf2/providers/registry:provider_mirror.bzl", "provider_mirror")
load("//tf2/providers/registry:filesystem_mirror.bzl", "filesystem_mirror")
load("//tf2/providers/core:info.bzl", "TfProviderConfigurationsInfo")

# Test provider mirror rule
def _provider_mirror_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that DefaultInfo is provided
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "provider_mirror should provide DefaultInfo"
    )

    # Check that files are generated
    files = target_under_test[DefaultInfo].files.to_list()
    asserts.true(
        env,
        len(files) > 0,
        "provider_mirror should generate files"
    )

    return analysistest.end(env)

provider_mirror_test = analysistest.make(_provider_mirror_test_impl)

# Test filesystem mirror
def _filesystem_mirror_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that DefaultInfo is provided
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "filesystem_mirror should provide DefaultInfo"
    )

    # Check runfiles are properly set
    runfiles = target_under_test[DefaultInfo].default_runfiles
    asserts.true(
        env,
        runfiles != None,
        "filesystem_mirror should provide runfiles"
    )

    return analysistest.end(env)

filesystem_mirror_test = analysistest.make(_filesystem_mirror_test_impl)

# Test provider configuration info
def _provider_configuration_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that TfProviderConfigurationsInfo is provided
    asserts.true(
        env,
        TfProviderConfigurationsInfo in target_under_test,
        "Provider configuration should provide TfProviderConfigurationsInfo"
    )

    # Check provider versions
    provider_info = target_under_test[TfProviderConfigurationsInfo]
    asserts.true(
        env,
        "aws" in provider_info.providers,
        "Should contain AWS provider"
    )

    asserts.equals(
        env,
        "6.12.0",
        provider_info.providers["aws"],
        "AWS provider version should match"
    )

    return analysistest.end(env)

provider_configuration_test = analysistest.make(_provider_configuration_test_impl)

# Test multiple providers
def _multiple_providers_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    provider_info = target_under_test[TfProviderConfigurationsInfo]

    # Check multiple providers are present
    asserts.true(
        env,
        len(provider_info.providers) >= 2,
        "Should support multiple providers"
    )

    asserts.true(
        env,
        "azurerm" in provider_info.providers,
        "Should contain Azure provider"
    )

    return analysistest.end(env)

multiple_providers_test = analysistest.make(_multiple_providers_test_impl)

# Test provider version constraints
def _provider_version_constraints_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    provider_info = target_under_test[TfProviderConfigurationsInfo]

    # Check version format
    for provider, version in provider_info.providers.items():
        parts = version.split(".")
        asserts.equals(
            env,
            3,
            len(parts),
            "Provider version should be in semver format (x.y.z)"
        )

        # Check each part is numeric
        for part in parts:
            asserts.true(
                env,
                part.isdigit(),
                "Version parts should be numeric"
            )

    return analysistest.end(env)

provider_version_constraints_test = analysistest.make(_provider_version_constraints_test_impl)

# Helper rule for creating test provider configurations
def _test_provider_config_impl(ctx):
    """Implementation for test provider configuration"""
    return [
        DefaultInfo(files = depset()),
        TfProviderConfigurationsInfo(
            providers = ctx.attr.providers,
        ),
    ]

test_provider_config = rule(
    implementation = _test_provider_config_impl,
    attrs = {
        "providers": attr.string_dict(
            doc = "Map of provider names to versions",
        ),
    },
)

# Test invalid provider configuration
def _invalid_provider_config_test_impl(ctx):
    env = analysistest.begin(ctx)

    # This test expects a failure, so we use expect_failure
    analysistest.expect_failure(
        env,
        "Invalid provider version format",
    )

    return analysistest.end(env)

invalid_provider_config_test = analysistest.make(
    _invalid_provider_config_test_impl,
    expect_failure = True,
)

# Helper to create mirror directories for testing
def _test_mirror_impl(ctx):
    """Create a test mirror directory structure"""
    mirror_dir = ctx.actions.declare_directory(ctx.label.name + "_mirror")

    # Create mirror structure
    ctx.actions.run_shell(
        outputs = [mirror_dir],
        command = """
            mkdir -p $1/registry.terraform.io/hashicorp/aws/6.12.0/linux_amd64
            echo "test provider binary" > $1/registry.terraform.io/hashicorp/aws/6.12.0/linux_amd64/terraform-provider-aws_v6.12.0_x5
        """,
        arguments = [mirror_dir.path],
    )

    return [DefaultInfo(files = depset([mirror_dir]))]

test_mirror = rule(
    implementation = _test_mirror_impl,
)

# Test suite setup
def provider_test_suite(name):
    """Create all provider test targets"""

    # Create test provider configurations
    test_provider_config(
        name = "test_single_provider",
        providers = {
            "aws": "6.12.0",
        },
    )

    provider_configuration_test(
        name = "provider_configuration_test",
        target_under_test = ":test_single_provider",
        size = "small",
    )

    # Test multiple providers
    test_provider_config(
        name = "test_multiple_providers",
        providers = {
            "aws": "6.12.0",
            "azurerm": "4.11.0",
            "google": "6.15.0",
        },
    )

    multiple_providers_test(
        name = "multiple_providers_test",
        target_under_test = ":test_multiple_providers",
        size = "small",
    )

    # Test version constraints
    test_provider_config(
        name = "test_version_constraints",
        providers = {
            "aws": "6.12.0",
            "azurerm": "4.0.0",
            "random": "3.6.3",
        },
    )

    provider_version_constraints_test(
        name = "provider_version_constraints_test",
        target_under_test = ":test_version_constraints",
        size = "small",
    )

    # Create test mirror
    test_mirror(
        name = "test_provider_mirror",
    )

    # Note: provider_mirror and filesystem_mirror rules require actual provider files
    # For now, we'll skip those tests or create minimal mocks

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":provider_configuration_test",
            ":multiple_providers_test",
            ":provider_version_constraints_test",
        ],
    )
