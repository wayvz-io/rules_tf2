# About Architecture

## Overview

rules_tf2 provides Bazel integration for Terraform, enabling management and validation of Terraform configurations in monorepos.

All external dependencies (providers, tools) are downloaded and cached by Bazel, so builds are reproducible and work offline after initial download.

## How tf_module Works

The `tf_module` macro is the primary entry point. From a single declaration, it generates:

- A module target containing your Terraform files
- Test targets for formatting, linting, validation, and documentation
- Utility targets for exports and doc generation

Provider requirements are inherited from dependencies—a parent module automatically includes providers from its children.

## Component Layout

### Public API (`tf2/def.bzl`)

All user-facing rules and macros are exported from here.

### Macros (`tf2/macros/`)

`tf_module` lives here. It generates the underlying targets.

### Core Rules (`tf2/tfcore/`)

Low-level rules for Terraform operations: staging files, running commands, executing tests.

### Tool Management (`tf2/tools/`)

Downloads platform-specific binaries: Terraform, TFLint, terraform-docs.

### Provider Management (`tf2/providers/`)

Downloads and caches provider binaries with hash verification.

## Information Flow

```
MODULE.bazel
    │
    ├── tf_providers extension
    │   └── Downloads providers → tf_provider_registry
    │
    └── tf_tools extension
        └── Downloads tools → tf_tool_registry

BUILD.bazel
    │
    └── tf_module macro
        ├── Creates module target (TfModuleInfo provider)
        ├── Creates test targets (format, lint, validate, etc.)
        └── Creates utility targets (export, docs generation)
```

## See Also

- [Provider System](providers.md) - Details on provider management
- [Validation](validation.md) - terraform validate
- [Linting](linting.md) - TFLint configuration
