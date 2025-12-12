# rules_tf2 Documentation Examples

## Tutorial Example: Getting Started

```markdown
# Tutorial: Your First Terraform Module with Bazel

In this tutorial, you'll create a simple Terraform module managed by Bazel using rules_tf2. By the end, you'll have a working module with automatic validation, linting, and documentation checks.

## What you'll learn
- How to set up rules_tf2 in a Bazel project
- How to create a tf_module target
- How to run the generated tests

## Prerequisites
- Bazel 7.0+ installed
- Basic familiarity with Terraform

## Step 1: Add rules_tf2 to your MODULE.bazel

Let's add rules_tf2 as a dependency. Open your `MODULE.bazel` and add:

\`\`\`starlark
bazel_dep(name = "rules_tf2", version = "0.1.0")
\`\`\`

You should see no errors when you run `bazel mod deps`.

## Step 2: Create your Terraform module

Now we'll create a simple module. Create a directory and files:

\`\`\`bash
mkdir -p terraform/modules/hello
\`\`\`

Create `terraform/modules/hello/main.tf`:

\`\`\`hcl
variable "name" {
  type        = string
  description = "Name to greet"
}

output "greeting" {
  value = "Hello, ${var.name}!"
}
\`\`\`

## Step 3: Create the BUILD.bazel file

Let's define our tf_module target:

\`\`\`starlark
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "hello",
    srcs = glob(["*.tf"]),
)
\`\`\`

## Step 4: Run the tests

Now let's verify everything works:

\`\`\`bash
bazel test //terraform/modules/hello:all
\`\`\`

You should see all tests pass, including format, lint, and validate checks.

## Next steps
- Add providers to your module
- Learn about tf_module options in the reference guide
```

---

## How-to Guide Example: Adding Providers

```markdown
# How to Add AWS Provider to a Module

## Prerequisites
- rules_tf2 configured in your project
- Provider versions defined in `versions.json`

## Steps

1. Add the provider to your `versions.json`:
   \`\`\`json
   {
     "providers": {
       "aws": "5.0.0"
     }
   }
   \`\`\`

2. Reference the provider in your `tf_module`:
   \`\`\`starlark
   tf_module(
       name = "my_module",
       srcs = glob(["*.tf"]),
       providers = ["@tf_provider_registry//:aws_5"],
   )
   \`\`\`

3. Regenerate lock files:
   \`\`\`bash
   bazel run //path/to:my_module_lock_update
   \`\`\`

## Verification

Run validation to confirm the provider is correctly configured:

\`\`\`bash
bazel test //path/to:my_module_validate_test
\`\`\`

## See also
- [Provider Architecture](../explanation/providers.md)
- [tf_module Reference](../reference/tf-module.md)
```

---

## Reference Example: tf_module

```markdown
# tf_module

Macro that creates a Terraform module target with comprehensive test suite.

## Synopsis

\`\`\`starlark
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "module_name",
    srcs = glob(["*.tf"]),
    providers = [],
    deps = [],
    data = [],
)
\`\`\`

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `name` | string | Yes | - | Unique name for this module |
| `srcs` | list of labels | Yes | - | Terraform source files (*.tf, *.tf.json) |
| `providers` | list of labels | No | `[]` | Provider dependencies from tf_provider_registry |
| `deps` | list of labels | No | `[]` | Other tf_module targets this module depends on |
| `data` | list of labels | No | `[]` | Additional data files needed at runtime |

## Generated Targets

For a module named `foo`, the following targets are created:

| Target | Description |
|--------|-------------|
| `:foo` | The module filegroup |
| `:foo_format_test` | Checks terraform fmt compliance |
| `:foo_lint_test` | Runs tflint checks |
| `:foo_validate_test` | Runs terraform validate |
| `:foo_doc_test` | Validates README.md documentation |
| `:foo_lock_update` | Updates provider lock file |

## Example

\`\`\`starlark
tf_module(
    name = "vpc",
    srcs = glob(["*.tf"]) + ["README.md"],
    providers = [
        "@tf_provider_registry//:aws_5",
    ],
    deps = [
        "//terraform/modules/subnet",
    ],
)
\`\`\`

## See also
- [tf_runner](tf-runner.md)
- [Provider Setup Guide](../guides/provider-setup.md)
```

---

## Explanation Example: Provider Architecture

```markdown
# About Provider Architecture

## Overview

rules_tf2 manages Terraform providers through a registry system that ensures hermetic, reproducible builds while supporting provider inheritance across module dependencies.

## Why a registry system?

Traditional Terraform workflows download providers on-demand, which creates several problems for Bazel builds:

1. **Non-hermetic builds**: Different runs might get different provider versions
2. **Network dependencies**: Builds fail without internet access
3. **Slow cold starts**: Each new environment re-downloads providers

The registry system solves these by pre-downloading providers and making them available as Bazel dependencies.

## How provider aliasing works

Providers are aliased by major version to balance stability with flexibility:

- `aws_5` refers to any AWS provider 5.x.x
- `azurerm_4` refers to any AzureRM provider 4.x.x

For 0.x providers, the alias includes minor version since breaking changes can occur:

- `time_0` for time provider 0.x.x

This convention follows semantic versioning expectations while keeping BUILD files readable.

## Provider inheritance

When module A depends on module B, module A inherits B's provider requirements:

\`\`\`
Module A (uses aws, depends on B)
└── Module B (uses aws, random)

A's lockfile contains: aws, random
\`\`\`

This means parent modules don't need to explicitly declare providers used only by their dependencies.

## Design decisions

### Why JSON lock files?

We chose JSON over Terraform's native `.terraform.lock.hcl` because:

1. Easier to parse and generate in Starlark
2. Can be aggregated across modules
3. Simpler merge conflict resolution

### Why download at analysis time?

Providers are downloaded during Bazel's analysis phase (via repository rules) rather than execution phase. This enables:

1. Provider binaries available to all actions
2. Caching across builds
3. Offline builds after initial download

## See also
- [Lock File Management](lock-files.md)
- [Provider Setup Guide](../guides/provider-setup.md)
```
