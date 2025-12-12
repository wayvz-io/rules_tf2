# Testing

rules_tf2 supports two testing approaches: `terraform validate` for syntax checking and `terraform test` for integration testing.

## Validation

Each `tf_module` generates a `*_validate_test` target that runs `terraform validate`.

### What Validation Checks

- HCL syntax is correct
- Required arguments are provided
- Attribute types match definitions
- References to resources, variables, and outputs resolve

Validation does **not** check semantic correctness (valid AMI IDs, correct instance types). Use [linting](linting.md) for that.

### How Validation Runs

1. Stages module files
2. Sets up filesystem mirror with required providers
3. Runs `terraform init` (cached providers, no network)
4. Runs `terraform validate`

### Modules Without Provider Definitions

`terraform validate` requires initialized providers. Child modules meant to be called from parents typically don't define their own provider configurations.

These modules can't validate standalone. Skip validation:

```starlark
tf_module(
    name = "child_module",
    srcs = ["main.tf", "variables.tf", "outputs.tf"],
    skip_validation = True,
)
```

## Terraform Test

For integration testing, use `tf_test` with `.tftest.hcl` files.

### Test File Format

Terraform test files define test cases:

```hcl
# basic.tftest.hcl
run "create_vpc" {
  command = plan

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block incorrect"
  }
}
```

### tf_test Rule

```starlark
tf_test(
    name = "vpc_test",
    module = ":vpc",
    test_files = ["basic.tftest.hcl"],
)
```

The `module` attribute points to the `tf_module` being tested. Test files are passed to `terraform test`.

### Gazelle Detection

When `.tftest.hcl` files exist in a module directory, Gazelle automatically generates a `tf_test` rule:

```starlark
tf_module(
    srcs = ["main.tf", "variables.tf"],
)

tf_test(
    module = ":tf_module",
    test_files = ["basic.tftest.hcl"],
)
```

## Running Tests

```bash
# All tests for a module
bazel test //path/to:all

# Just validation
bazel test //path/to:my_module_validate_test

# Integration tests
bazel test //path/to:my_module_test
```
