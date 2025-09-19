# Basic Module Example

This example demonstrates a simple Terraform module using Bazel's tf_module rule.

## Overview

This module creates:
- An AWS EC2 instance
- A security group with configurable SSH access
- Random naming for uniqueness

## Usage

### In Bazel

```starlark
load("//tf2:def.bzl", "tf_module")

tf_module(
    name = "my_infrastructure",
    modules = ["//examples/basic_module"],
    providers = [
        "@tf_provider_registry//:aws_6",
        "@tf_provider_registry//:random_3",
    ],
)
```

### Testing

```bash
# Run all tests
bazel test //examples/basic_module:all

# Run specific tests
bazel test //examples/basic_module:basic_module_validate_test
bazel test //examples/basic_module:basic_module_format_test
bazel test //examples/basic_module:basic_module_lint_test
```

### Maintenance

```bash
# Format the code
bazel run //examples/basic_module:basic_module_format

# Generate documentation
bazel run //examples/basic_module:basic_module_generate_docs

# Update provider versions
bazel run //examples/basic_module:basic_module_generate_versions
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ami_id | The AMI ID for the EC2 instance | `string` | n/a | yes |
| instance_type | The EC2 instance type | `string` | `"t3.micro"` | no |
| ssh_cidr_blocks | CIDR blocks allowed for SSH access | `list(string)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| instance_id | The ID of the EC2 instance |
| instance_public_ip | The public IP address of the EC2 instance |
| security_group_id | The ID of the security group |
| instance_name | The randomly generated name for this instance |