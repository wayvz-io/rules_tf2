# About Validation

## Overview

rules_tf2 generates a `*_validate_test` target for each `tf_module` that runs `terraform validate`.

## What terraform validate Checks

`terraform validate` checks that a configuration is syntactically valid:

- HCL syntax is correct
- Required arguments are provided
- Attribute types match their definitions
- References to resources, variables, and outputs resolve

It does **not** check whether values are semantically correct (e.g., valid AMI IDs, correct instance types). For that, use [TFLint](linting.md).

## Modules Without Provider Definitions

`terraform validate` requires providers to be initialized. Modules that are meant to be called from other modules typically don't define their own provider configurations—they inherit providers from the calling module.

These modules can't run `terraform validate` standalone. Use `skip_validation = True`:

```starlark
tf_module(
    name = "child_module",
    srcs = glob(["*.tf"]),
    skip_validation = True,
)
```

## How Validation Runs

For modules that can be validated, rules_tf2:

1. Stages the module files
2. Sets up a filesystem mirror with required providers
3. Runs `terraform init` (using cached providers)
4. Runs `terraform validate`

## See Also

- [Linting](linting.md) - TFLint static analysis
- [Architecture](architecture.md)
