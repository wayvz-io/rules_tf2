# rules_tf2

Terraform rules for Bazel - hermetic, reproducible infrastructure builds.

rules_tf2 is a Bazel module that provides Terraform integration for Bazel builds. It manages Terraform modules with integrated testing, provider management, and Terraform Cloud support.

## Features

- **Hermetic builds**: Terraform providers are downloaded and cached by Bazel, ensuring reproducible builds
- **Integrated testing**: Automatic generation of format, lint, validate, and documentation tests
- **Provider management**: Declarative provider configuration with version pinning and lock files
- **Terraform Cloud integration**: Native support for Terraform Cloud workspaces
- **Publishing**: Push modules to Terraform Registry or OCI registries

## Quick Start

Add rules_tf2 to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_tf2", version = "0.1.0")
```

Create a Terraform module with automatic testing:

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "my_module",
    srcs = glob(["*.tf"]) + ["README.md"],
)
```

Run all tests:

```bash
bazel test //path/to:my_module_all
```

## Documentation Structure

This documentation follows the [Diataxis](https://diataxis.fr/) framework:

- **[Tutorials](tutorials/README.md)**: Learning-oriented guides for newcomers
- **[How-to Guides](guides/README.md)**: Task-oriented instructions for specific goals
- **[Reference](reference/README.md)**: Technical descriptions of rules, macros, and APIs
- **[Explanation](explanation/README.md)**: Understanding-oriented discussions of concepts

## Status

**Alpha** - Core functionality works but APIs may change.
