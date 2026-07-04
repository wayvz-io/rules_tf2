# Rules

Core Bazel rules and macros for Terraform module management.

## Overview

| Rule | Description |
|------|-------------|
| [tf_module](tf-module.md) | Main macro for creating Terraform modules with testing |
| [tf_runner](tf-runner.md) | Run arbitrary Terraform commands against a module |
| [tf_test](tf-test.md) | Run Terraform native tests (`.tftest.hcl`) |
| [tf_variables](tf-variables.md) | Collect variable files for use with runners |
| [tf_file_export](tf-file-export.md) | Export processed modules to filesystem |

## tf_module

The primary user-facing API. Creates a Terraform module target with automatic test generation:

```starlark
tf_module(
    name = "my_module",
    srcs = [
        "main.tf",
        "outputs.tf",
        "README.md",
        "terraform.tf",
        "variables.tf",
    ],
    providers = ["@tf_provider_registry//:aws_5"],
)
```

This generates 10+ test targets automatically, including format, lint, validate, and documentation checks.

## tf_runner

For running arbitrary Terraform commands:

```starlark
tf_runner(
    name = "runner",
    stack = ":my_module",
    variables = ":my_vars",
)
```

```bash
bazel run //:runner -- plan
bazel run //:runner -- apply
```
