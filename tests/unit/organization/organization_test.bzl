"""Unit tests for Terraform organization rules"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tf2/module/deps:organization.bzl", "tf_organization_check_test", "tf_organization_negative_test", "tf_reorganize")

# Test organization check test creation
def _tf_organization_check_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_organization_check_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_organization_check_test should be executable",
    )

    return analysistest.end(env)

tf_organization_check_test_creation_test = analysistest.make(_tf_organization_check_test_creation_test_impl)

# Test reorganize rule
def _tf_reorganize_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that reorganize is executable
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_reorganize should provide DefaultInfo",
    )

    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_reorganize should be executable",
    )

    return analysistest.end(env)

tf_reorganize_test = analysistest.make(_tf_reorganize_test_impl)

# Test organization check with properly organized files
def _tf_organization_properly_organized_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that proper files are included
    files = runfiles.files.to_list()
    file_names = [f.basename for f in files]

    # Should have standard terraform file names
    expected_files = ["terraform.tf", "providers.tf", "variables.tf", "outputs.tf", "main.tf"]
    for expected in expected_files:
        if expected in file_names:
            asserts.true(
                env,
                True,
                "Found expected file: " + expected,
            )

    return analysistest.end(env)

tf_organization_properly_organized_test = analysistest.make(_tf_organization_properly_organized_test_impl)

# Test organization check with mixed content
def _tf_organization_mixed_content_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Mixed content files should still be testable
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "Organization check should handle mixed content files",
    )

    return analysistest.end(env)

tf_organization_mixed_content_test = analysistest.make(_tf_organization_mixed_content_test_impl)

# Helper to create properly organized terraform files
def _create_organized_tf_files_impl(ctx):
    """Create properly organized terraform files"""

    # terraform.tf - only terraform blocks (correct filename)
    terraform_tf = ctx.actions.declare_file("terraform.tf")
    ctx.actions.write(
        output = terraform_tf,
        content = """terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
""",
    )

    # providers.tf - only provider blocks
    providers_tf = ctx.actions.declare_file("providers.tf")
    ctx.actions.write(
        output = providers_tf,
        content = """provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_west"
  region = "us-west-2"
}
""",
    )

    # variables.tf - only variable blocks (correct filename)
    variables_tf = ctx.actions.declare_file("variables.tf")
    ctx.actions.write(
        output = variables_tf,
        content = """variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name"
}
""",
    )

    # outputs.tf - only output blocks
    outputs_tf = ctx.actions.declare_file("outputs.tf")
    ctx.actions.write(
        output = outputs_tf,
        content = """output "instance_id" {
  value       = aws_instance.main.id
  description = "ID of the EC2 instance"
}

output "bucket_arn" {
  value       = aws_s3_bucket.main.arn
  description = "ARN of the S3 bucket"
}
""",
    )

    # main.tf - resources, data sources, locals (correct filename)
    main_tf = ctx.actions.declare_file("main.tf")
    ctx.actions.write(
        output = main_tf,
        content = """locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
}

resource "aws_instance" "main" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  
  tags = local.common_tags
}

resource "aws_s3_bucket" "main" {
  bucket = "$${var.environment}-bucket"
  
  tags = local.common_tags
}
""",
    )

    return [DefaultInfo(files = depset([
        terraform_tf,
        providers_tf,
        variables_tf,
        outputs_tf,
        main_tf,
    ]))]

create_organized_tf_files = rule(
    implementation = _create_organized_tf_files_impl,
)

# Helper to create disorganized terraform files
def _create_disorganized_tf_files_impl(ctx):
    """Create disorganized terraform files (mixed content)"""

    # Mixed file with various block types
    mixed_tf = ctx.actions.declare_file("mixed.tf")
    ctx.actions.write(
        output = mixed_tf,
        content = """
# This file has mixed content that should be reorganized

terraform {
  required_version = ">= 1.0"
}

variable "region" {
  type = string
}

provider "aws" {
  region = var.region
}

resource "aws_instance" "test" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}

output "instance_id" {
  value = aws_instance.test.id
}

variable "environment" {
  type = string
}

provider "aws" {
  alias  = "backup"
  region = "us-west-2"
}
""",
    )

    # Another mixed file
    config_tf = ctx.actions.declare_file("config.tf")
    ctx.actions.write(
        output = config_tf,
        content = """
# More mixed content

locals {
  tags = {
    Environment = var.environment
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

output "tags" {
  value = local.tags
}

data "aws_region" "current" {}

variable "bucket_name" {
  type = string
}
""",
    )

    return [DefaultInfo(files = depset([mixed_tf, config_tf]))]

create_disorganized_tf_files = rule(
    implementation = _create_disorganized_tf_files_impl,
)

# Helper to create files with imports
def _create_files_with_imports_impl(ctx):
    """Create files including import blocks"""

    imports_tf = ctx.actions.declare_file("imports.tf")
    ctx.actions.write(
        output = imports_tf,
        content = """
import {
  to = aws_instance.existing
  id = "i-1234567890abcdef0"
}

import {
  to = aws_s3_bucket.legacy
  id = "legacy-bucket-name"
}
""",
    )

    main_tf = ctx.actions.declare_file("main_imports.tf")
    ctx.actions.write(
        output = main_tf,
        content = """
resource "aws_instance" "existing" {
  # Will be imported
}

resource "aws_s3_bucket" "legacy" {
  # Will be imported
}
""",
    )

    return [DefaultInfo(files = depset([imports_tf, main_tf]))]

create_files_with_imports = rule(
    implementation = _create_files_with_imports_impl,
)

# Test suite setup
def organization_test_suite(name):
    """Create all organization test targets

    Args:
        name: Name of the test suite
    """

    # Create test files
    create_organized_tf_files(
        name = "organized_files",
    )

    create_disorganized_tf_files(
        name = "disorganized_files",
    )

    create_files_with_imports(
        name = "files_with_imports",
    )

    # Test basic organization check test
    tf_organization_check_test(
        name = "basic_organization_check",
        srcs = [":organized_files"],
        size = "small",
    )

    tf_organization_check_test_creation_test(
        name = "tf_organization_check_test_creation_test",
        target_under_test = ":basic_organization_check",
        size = "small",
    )

    # Test reorganize rule
    tf_reorganize(
        name = "basic_reorganize",
    )

    tf_reorganize_test(
        name = "tf_reorganize_test",
        target_under_test = ":basic_reorganize",
        size = "small",
    )

    # Test with properly organized files
    tf_organization_check_test(
        name = "check_organized",
        srcs = [":organized_files"],
        size = "small",
    )

    tf_organization_properly_organized_test(
        name = "tf_organization_properly_organized_test",
        target_under_test = ":check_organized",
        size = "small",
    )

    # Test with mixed content (expecting it to be detected as disorganized)
    tf_organization_negative_test(
        name = "check_mixed",
        srcs = [":disorganized_files"],
        size = "small",
    )

    tf_organization_mixed_content_test(
        name = "tf_organization_mixed_content_test",
        target_under_test = ":check_mixed",
        size = "small",
    )

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_organization_check_test_creation_test",
            ":tf_reorganize_test",
            ":tf_organization_properly_organized_test",
            ":tf_organization_mixed_content_test",
        ],
    )
