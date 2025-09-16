# Module with Dependencies Example

This example demonstrates how to compose Terraform modules together using Bazel's module dependency system.

## Overview

This module:
- Uses the `basic_module` as a dependency to create a web server
- Adds a load balancer in front of the web server
- Shows how to pass variables between modules
- Demonstrates module composition patterns

## Key Concepts

### Module Dependencies

In the BUILD file, we declare module dependencies:
```starlark
tf_module(
    name = "module_with_dependencies",
    modules = [
        "//examples/basic_module",
    ],
    # ... providers ...
)
```

This ensures:
1. The dependency is built and validated first
2. The module source is correctly rewritten to reference the processed module
3. All provider requirements are aggregated

### Module References

In Terraform code, reference the module:
```hcl
module "web_server" {
  source = "./modules/basic_module"
  # ... configuration ...
}
```

The Bazel rules automatically handle path rewriting to make the module available at the expected location.

## Usage

### Testing

```bash
# Run all tests
bazel test //examples/module_with_dependencies:all

# Validate the complete module tree
bazel test //examples/module_with_dependencies:module_with_dependencies_validate_test
```

### Using in Another Module

```starlark
tf_module(
    name = "my_app",
    modules = ["//examples/module_with_dependencies"],
    providers = [
        "@tf_provider_registry//:aws_6",
        "@tf_provider_registry//:random_3",
    ],
)
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name (e.g., dev, staging, prod) | `string` | n/a | yes |
| vpc_id | The VPC ID where resources will be created | `string` | n/a | yes |
| public_subnet_ids | List of public subnet IDs for the load balancer | `list(string)` | n/a | yes |
| web_ami_id | AMI ID for the web server instance | `string` | n/a | yes |
| web_instance_type | Instance type for the web server | `string` | `"t3.small"` | no |
| admin_cidr_blocks | CIDR blocks allowed for administrative SSH access | `list(string)` | `[]` | no |
| common_tags | Common tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| load_balancer_dns | DNS name of the load balancer |
| load_balancer_arn | ARN of the load balancer |
| web_instance_id | ID of the web server instance |
| web_instance_ip | Public IP of the web server instance |
| web_security_group_id | Security group ID of the web server |