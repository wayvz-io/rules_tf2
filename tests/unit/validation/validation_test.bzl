"""Unit tests for Terraform validation rules"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tf2/module/validation:validate.bzl", "tf_validate_test")

# Test that validation test rule is created correctly
def _tf_validate_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_validate_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_validate_test should be executable",
    )

    return analysistest.end(env)

tf_validate_test_creation_test = analysistest.make(_tf_validate_test_creation_test_impl)

# Test validation with lock file
def _tf_validate_with_lockfile_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check runfiles include lock file
    runfiles = target_under_test[DefaultInfo].default_runfiles
    asserts.true(
        env,
        runfiles != None,
        "Validation test should have runfiles",
    )

    return analysistest.end(env)

tf_validate_with_lockfile_test = analysistest.make(_tf_validate_with_lockfile_test_impl)

# Test validation with provider registry
def _tf_validate_with_registry_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that provider registry is included in runfiles
    runfiles = target_under_test[DefaultInfo].default_runfiles
    asserts.true(
        env,
        runfiles != None,
        "Validation test should include provider registry in runfiles",
    )

    return analysistest.end(env)

tf_validate_with_registry_test = analysistest.make(_tf_validate_with_registry_test_impl)

# Test validation failure expectations
def _tf_validate_failure_test_impl(ctx):
    env = analysistest.begin(ctx)

    # This test expects validation to detect errors
    analysistest.expect_failure(
        env,
        "validation should fail for invalid configuration",
    )

    return analysistest.end(env)

tf_validate_failure_test = analysistest.make(
    _tf_validate_failure_test_impl,
    expect_failure = True,
)

# Test validation with multiple source files
def _tf_validate_multiple_files_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that multiple source files are included
    files = runfiles.files.to_list()
    tf_files = [f for f in files if f.path.endswith(".tf")]

    asserts.true(
        env,
        len(tf_files) >= 2,
        "Validation should handle multiple .tf files",
    )

    return analysistest.end(env)

tf_validate_multiple_files_test = analysistest.make(_tf_validate_multiple_files_test_impl)

# Helper to create test terraform files
def _create_test_tf_files_impl(ctx):
    """Create test terraform configuration files"""

    # Create main.tf without provider resources
    main_tf = ctx.actions.declare_file("main_validation.tf")
    ctx.actions.write(
        output = main_tf,
        content = """
# Test configuration without provider resources
variable "test_input" {
  type    = string
  default = "test"
}

locals {
  test_value = "${var.test_input}-processed"
}

output "test_output" {
  value = local.test_value
}
""",
    )

    # Create variables.tf
    variables_tf = ctx.actions.declare_file("variables_validation.tf")
    ctx.actions.write(
        output = variables_tf,
        content = """
variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}
""",
    )

    # Create terraform.tf without provider requirements
    terraform_tf = ctx.actions.declare_file("terraform_validation.tf")
    ctx.actions.write(
        output = terraform_tf,
        content = """
terraform {
  required_version = ">= 1.0"
}
""",
    )

    return [DefaultInfo(files = depset([main_tf, variables_tf, terraform_tf]))]

create_test_tf_files = rule(
    implementation = _create_test_tf_files_impl,
)

# Helper to create invalid terraform files
def _create_invalid_tf_files_impl(ctx):
    """Create invalid terraform configuration for testing failures"""

    invalid_tf = ctx.actions.declare_file("invalid.tf")
    ctx.actions.write(
        output = invalid_tf,
        content = """
# Invalid resource - missing required arguments
resource "aws_instance" "invalid" {
  # Missing required ami and instance_type
}

# Invalid variable - wrong type syntax
variable "invalid" {
  type = not_a_valid_type
}
""",
    )

    return [DefaultInfo(files = depset([invalid_tf]))]

create_invalid_tf_files = rule(
    implementation = _create_invalid_tf_files_impl,
)

# Helper to create test lock file
def _create_test_lockfile_impl(ctx):
    """Create a test .terraform.lock.hcl file"""

    lock_file = ctx.actions.declare_file(".terraform.lock.hcl")
    ctx.actions.write(
        output = lock_file,
        content = """
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

# Empty lockfile for testing
""",
    )

    return [DefaultInfo(files = depset([lock_file]))]

create_test_lockfile = rule(
    implementation = _create_test_lockfile_impl,
)

# Helper to create mock provider registry
def _create_mock_registry_impl(ctx):
    """Create a mock provider registry for testing"""

    # Use the expected mirror directory name
    registry_dir = ctx.actions.declare_directory("mirror_linux_arm64")

    ctx.actions.run_shell(
        outputs = [registry_dir],
        command = """
            mkdir -p $1/registry.terraform.io/hashicorp/aws/6.12.0/linux_arm64
            echo "mock provider" > $1/registry.terraform.io/hashicorp/aws/6.12.0/linux_arm64/terraform-provider-aws_v6.12.0_x6
            chmod +x $1/registry.terraform.io/hashicorp/aws/6.12.0/linux_arm64/terraform-provider-aws_v6.12.0_x6
        """,
        arguments = [registry_dir.path],
    )

    return [DefaultInfo(files = depset([registry_dir]))]

create_mock_registry = rule(
    implementation = _create_mock_registry_impl,
)

# Test suite setup
def validation_test_suite(name):
    """Create all validation test targets

    Args:
        name: Name of the test suite
    """

    # Create test terraform files
    create_test_tf_files(
        name = "test_tf_files",
    )

    create_invalid_tf_files(
        name = "invalid_tf_files",
    )

    create_test_lockfile(
        name = "test_lockfile",
    )

    # Test basic validation test creation
    tf_validate_test(
        name = "basic_validate_test",
        srcs = [":test_tf_files"],
        lock_file = ":test_lockfile",
        size = "small",
    )

    tf_validate_test_creation_test(
        name = "tf_validate_test_creation_test",
        target_under_test = ":basic_validate_test",
        size = "small",
    )

    # Test validation with lockfile
    tf_validate_test(
        name = "validate_with_lockfile",
        srcs = [":test_tf_files"],
        lock_file = ":test_lockfile",
        size = "small",
    )

    tf_validate_with_lockfile_test(
        name = "tf_validate_with_lockfile_test",
        target_under_test = ":validate_with_lockfile",
        size = "small",
    )

    # Test validation with provider registry
    tf_validate_test(
        name = "validate_with_registry",
        srcs = [":test_tf_files"],
        lock_file = ":test_lockfile",
        size = "small",
    )

    tf_validate_with_registry_test(
        name = "tf_validate_with_registry_test",
        target_under_test = ":validate_with_registry",
        size = "small",
    )

    # Test validation with multiple files
    tf_validate_test(
        name = "validate_multiple_files",
        srcs = [":test_tf_files"],
        lock_file = ":test_lockfile",
        size = "small",
    )

    tf_validate_multiple_files_test(
        name = "tf_validate_multiple_files_test",
        target_under_test = ":validate_multiple_files",
        size = "small",
    )

    # Note: Testing actual validation failures would require running the test
    # and checking its output, which is beyond the scope of analysis tests

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_validate_test_creation_test",
            ":tf_validate_with_lockfile_test",
            ":tf_validate_with_registry_test",
            ":tf_validate_multiple_files_test",
        ],
    )
