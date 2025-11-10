"""Unit tests for Terraform lint rules"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tf2/tflint:test.bzl", "tf_lint_negative_test", "tf_lint_test")

# Test that lint test rule is created correctly
def _tf_lint_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_lint_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_lint_test should be executable",
    )

    return analysistest.end(env)

tf_lint_test_creation_test = analysistest.make(_tf_lint_test_creation_test_impl)

# Test lint with config file
def _tf_lint_with_config_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that config file is included in runfiles
    files = runfiles.files.to_list()
    config_files = [f for f in files if f.basename == ".tflint.hcl"]

    asserts.true(
        env,
        len(config_files) > 0,
        "Lint test should include config file when specified",
    )

    return analysistest.end(env)

tf_lint_with_config_test = analysistest.make(_tf_lint_with_config_test_impl)

# Test lint without config file
def _tf_lint_without_config_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Should still be valid without config
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "Lint test should work without config file",
    )

    return analysistest.end(env)

tf_lint_without_config_test = analysistest.make(_tf_lint_without_config_test_impl)

# Test lint with multiple source files
def _tf_lint_multiple_files_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that multiple source files are included
    files = runfiles.files.to_list()
    tf_files = [f for f in files if f.path.endswith(".tf")]

    asserts.true(
        env,
        len(tf_files) >= 2,
        "Lint test should handle multiple .tf files",
    )

    return analysistest.end(env)

tf_lint_multiple_files_test = analysistest.make(_tf_lint_multiple_files_test_impl)

# Helper to create test terraform files with lint issues
def _create_files_with_lint_issues_impl(ctx):
    """Create terraform files with common lint issues"""

    main_tf = ctx.actions.declare_file("lint_issues_main.tf")
    ctx.actions.write(
        output = main_tf,
        content = """
# File with various lint issues

# Local with no description
locals {
  # Using deprecated interpolation syntax
  value = "${var.region}-test"
}

# Output without description
output "test" {
  value = local.value
}

# Variable reference that doesn't exist
output "bad_reference" {
  value = var.nonexistent_variable
}
""",
    )

    variables_tf = ctx.actions.declare_file("lint_issues_variables.tf")
    ctx.actions.write(
        output = variables_tf,
        content = """
# Variables with issues

# Missing description
variable "region" {
  type = string
}

# Missing type constraint  
variable "untyped_var" {
  description = "This variable has no type"
}

# Unused variable
variable "unused" {
  type        = string
  description = "This variable is never referenced"
}
""",
    )

    return [DefaultInfo(files = depset([main_tf, variables_tf]))]

create_files_with_lint_issues = rule(
    implementation = _create_files_with_lint_issues_impl,
)

# Helper to create clean terraform files
def _create_clean_tf_files_impl(ctx):
    """Create terraform files without lint issues"""

    main_tf = ctx.actions.declare_file("clean_main.tf")
    ctx.actions.write(
        output = main_tf,
        content = """
# Clean terraform file with no lint issues

locals {
  environment = var.environment
  region      = var.region
}

output "environment" {
  value       = local.environment
  description = "The environment name"
}

output "region" {
  value       = local.region
  description = "The region name"
}
""",
    )

    variables_tf = ctx.actions.declare_file("clean_variables.tf")
    ctx.actions.write(
        output = variables_tf,
        content = """
variable "environment" {
  type        = string
  description = "The deployment environment"
  default     = "dev"
}

variable "region" {
  type        = string
  description = "The deployment region"
  default     = "us-east-1"
}
""",
    )

    terraform_tf = ctx.actions.declare_file("clean_terraform.tf")
    ctx.actions.write(
        output = terraform_tf,
        content = """
terraform {
  required_version = ">= 1.0"
}
""",
    )

    return [DefaultInfo(files = depset([main_tf, variables_tf, terraform_tf]))]

create_clean_tf_files = rule(
    implementation = _create_clean_tf_files_impl,
)

# Helper to create tflint config
def _create_tflint_config_impl(ctx):
    """Create a .tflint.hcl configuration file"""

    config = ctx.actions.declare_file(".tflint.hcl")
    ctx.actions.write(
        output = config,
        content = """
# TFLint configuration

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}
""",
    )

    return [DefaultInfo(files = depset([config]))]

create_tflint_config = rule(
    implementation = _create_tflint_config_impl,
)

# Test suite setup
def lint_test_suite(name):
    """Create all lint test targets

    Args:
        name: Name of the test suite
    """

    # Create test files
    create_files_with_lint_issues(
        name = "files_with_issues",
    )

    create_clean_tf_files(
        name = "clean_files",
    )

    create_tflint_config(
        name = "tflint_config",
    )

    # Test basic lint test creation
    tf_lint_test(
        name = "basic_lint_test",
        srcs = [":clean_files"],
        size = "small",
    )

    tf_lint_test_creation_test(
        name = "tf_lint_test_creation_test",
        target_under_test = ":basic_lint_test",
        size = "small",
    )

    # Test lint with config
    tf_lint_test(
        name = "lint_with_config",
        srcs = [":clean_files"],
        config = ":tflint_config",
        size = "small",
    )

    tf_lint_with_config_test(
        name = "tf_lint_with_config_test",
        target_under_test = ":lint_with_config",
        size = "small",
    )

    # Test lint without config
    tf_lint_test(
        name = "lint_without_config",
        srcs = [":clean_files"],
        size = "small",
    )

    tf_lint_without_config_test(
        name = "tf_lint_without_config_test",
        target_under_test = ":lint_without_config",
        size = "small",
    )

    # Test with multiple files (expecting issues to be found)
    tf_lint_negative_test(
        name = "lint_multiple_files",
        srcs = [":files_with_issues"],
        size = "small",
    )

    tf_lint_multiple_files_test(
        name = "tf_lint_multiple_files_test",
        target_under_test = ":lint_multiple_files",
        size = "small",
    )

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_lint_test_creation_test",
            ":tf_lint_with_config_test",
            ":tf_lint_without_config_test",
            ":tf_lint_multiple_files_test",
        ],
    )
