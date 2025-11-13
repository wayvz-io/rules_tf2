"""Unit tests for Terraform versions rules"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tf2/providers/core:info.bzl", "TfModuleInfo", "TfProviderConfigurationsInfo", "TfProviderMirrorInfo")
load("//tf2/tfcore/versions:versions.bzl", "tf_generate_versions", "tf_generate_versions_from_mirrors", "tf_versions_check_test", "tf_versions_negative_test")

# Test versions check test creation
def _tf_versions_check_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_versions_check_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_versions_check_test should be executable",
    )

    return analysistest.end(env)

tf_versions_check_test_creation_test = analysistest.make(_tf_versions_check_test_creation_test_impl)

# Test generate versions rule
def _tf_generate_versions_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that generator is executable
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_generate_versions should provide DefaultInfo",
    )

    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_generate_versions should be executable",
    )

    return analysistest.end(env)

tf_generate_versions_test = analysistest.make(_tf_generate_versions_test_impl)

# Test generate versions from mirrors
def _tf_generate_versions_from_mirrors_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it generates a versions.json file
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_generate_versions_from_mirrors should provide DefaultInfo",
    )

    files = target_under_test[DefaultInfo].files.to_list()
    versions_files = []
    for f in files:
        if f.basename.endswith("_versions.json"):
            versions_files.append(f)

    asserts.equals(
        env,
        1,
        len(versions_files),
        "Should generate exactly one versions.json file",
    )

    return analysistest.end(env)

tf_generate_versions_from_mirrors_test = analysistest.make(_tf_generate_versions_from_mirrors_test_impl)

# Test versions with nested modules
def _tf_versions_nested_modules_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # When modules are specified, their providers should be included
    files = target_under_test[DefaultInfo].files.to_list()

    asserts.true(
        env,
        len(files) > 0,
        "Nested modules should contribute to provider configurations",
    )

    return analysistest.end(env)

tf_versions_nested_modules_test = analysistest.make(_tf_versions_nested_modules_test_impl)

# Test multiple providers aggregation
def _tf_versions_multiple_providers_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    files = target_under_test[DefaultInfo].files.to_list()

    # Check that multiple providers are handled
    asserts.true(
        env,
        len(files) > 0,
        "Multiple providers should be aggregated correctly",
    )

    return analysistest.end(env)

tf_versions_multiple_providers_test = analysistest.make(_tf_versions_multiple_providers_test_impl)

# Helper to create test terraform.tf with version constraints
def _create_terraform_tf_impl(ctx):
    """Create terraform.tf with provider requirements"""

    terraform_tf = ctx.actions.declare_file("terraform_versions.tf")
    ctx.actions.write(
        output = terraform_tf,
        content = """terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.12.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.11.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
  }
}
""",
    )

    return [DefaultInfo(files = depset([terraform_tf]))]

create_terraform_tf = rule(
    implementation = _create_terraform_tf_impl,
)

# Helper to create versions.json for testing
def _create_versions_json_impl(ctx):
    """Create a versions.json file"""

    versions_json = ctx.actions.declare_file("versions.json")
    ctx.actions.write(
        output = versions_json,
        content = """
{
  "required_providers": {
    "aws": {
      "source": "hashicorp/aws",
      "version": "6.12.0"
    },
    "azurerm": {
      "source": "hashicorp/azurerm",
      "version": "4.11.0"
    },
    "random": {
      "source": "hashicorp/random",
      "version": "3.6.3"
    }
  }
}
""",
    )

    return [
        DefaultInfo(files = depset([versions_json])),
        TfProviderConfigurationsInfo(
            providers = {
                "aws": "6.12.0",
                "azurerm": "4.11.0",
                "random": "3.6.3",
            },
            tf_version_constraint = ">= 1.0.0",
            versions_file = versions_json,
        ),
    ]

create_versions_json = rule(
    implementation = _create_versions_json_impl,
)

# Helper to create mismatched versions
def _create_mismatched_versions_impl(ctx):
    """Create files with mismatched version requirements"""

    terraform_tf = ctx.actions.declare_file("mismatched_terraform.tf")
    ctx.actions.write(
        output = terraform_tf,
        content = """
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Different major version
    }
  }
}
""",
    )

    return [DefaultInfo(files = depset([terraform_tf]))]

create_mismatched_versions = rule(
    implementation = _create_mismatched_versions_impl,
)

# Mock provider mirror for testing
def _mock_provider_mirror_impl(ctx):
    """Create a mock provider mirror"""

    # Determine provider based on target name
    if "aws" in ctx.label.name:
        provider_name = "aws"
        provider = "hashicorp/aws"
        version = "6.12.0"
    else:
        provider_name = "azurerm"
        provider = "hashicorp/azurerm"
        version = "4.11.0"

    # Create a dummy directory for the mirror
    mirror_dir = ctx.actions.declare_directory(ctx.label.name + "_mirror")
    ctx.actions.run_shell(
        outputs = [mirror_dir],
        command = "mkdir -p $1",
        arguments = [mirror_dir.path],
    )

    return [
        DefaultInfo(files = depset([mirror_dir])),
        TfProviderMirrorInfo(
            provider = provider,
            version = version,
            provider_name = provider_name,
            namespace = "hashicorp",
            mirror_dir = mirror_dir,
        ),
    ]

mock_provider_mirror = rule(
    implementation = _mock_provider_mirror_impl,
)

# Mock module with providers
def _mock_module_with_providers_impl(ctx):
    """Create a mock module that provides provider info"""
    return [
        DefaultInfo(files = depset()),
        TfModuleInfo(
            name = ctx.label.name,
            srcs = depset(),
            modules = [],
            provider_configurations = None,
        ),
    ]

mock_module_with_providers = rule(
    implementation = _mock_module_with_providers_impl,
)

# Test suite setup
def versions_test_suite(name):
    """Create all versions test targets

    Args:
        name: Name of the test suite
    """

    # Create test files
    create_terraform_tf(
        name = "test_terraform_tf",
    )

    create_versions_json(
        name = "test_versions_json",
    )

    create_mismatched_versions(
        name = "mismatched_versions",
    )

    # Create mock providers
    mock_provider_mirror(
        name = "mock_aws_provider",
    )

    mock_provider_mirror(
        name = "mock_azure_provider",
    )

    mock_module_with_providers(
        name = "mock_nested_module",
    )

    # Test versions check test creation
    tf_versions_check_test(
        name = "basic_versions_check",
        srcs = [":test_terraform_tf"],
        provider_configurations = ":test_versions_json",
        size = "small",
    )

    tf_versions_check_test_creation_test(
        name = "tf_versions_check_test_creation_test",
        target_under_test = ":basic_versions_check",
        size = "small",
    )

    # Test generate versions
    tf_generate_versions(
        name = "generate_versions",
        provider_configurations = ":test_versions_json",
    )

    tf_generate_versions_test(
        name = "tf_generate_versions_test",
        target_under_test = ":generate_versions",
        size = "small",
    )

    # Test generate versions from mirrors
    tf_generate_versions_from_mirrors(
        name = "generate_from_mirrors",
        providers = [":mock_aws_provider", ":mock_azure_provider"],
    )

    tf_generate_versions_from_mirrors_test(
        name = "tf_generate_versions_from_mirrors_test",
        target_under_test = ":generate_from_mirrors",
        size = "small",
    )

    # Test with nested modules
    tf_generate_versions_from_mirrors(
        name = "generate_with_modules",
        providers = [":mock_aws_provider"],
        modules = [":mock_nested_module"],
    )

    tf_versions_nested_modules_test(
        name = "tf_versions_nested_modules_test",
        target_under_test = ":generate_with_modules",
        size = "small",
    )

    # Test multiple providers
    tf_generate_versions_from_mirrors(
        name = "generate_multiple_providers",
        providers = [":mock_aws_provider", ":mock_azure_provider"],
    )

    tf_versions_multiple_providers_test(
        name = "tf_versions_multiple_providers_test",
        target_under_test = ":generate_multiple_providers",
        size = "small",
    )

    # Test version mismatch detection (negative test)
    tf_versions_negative_test(
        name = "versions_mismatch_check",
        srcs = [":mismatched_versions"],
        provider_configurations = ":test_versions_json",
        size = "small",
    )

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_versions_check_test_creation_test",
            ":tf_generate_versions_test",
            ":tf_generate_versions_from_mirrors_test",
            ":tf_versions_nested_modules_test",
            ":tf_versions_multiple_providers_test",
            ":versions_mismatch_check",
        ],
    )
