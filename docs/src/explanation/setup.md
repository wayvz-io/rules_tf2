# About Setup

## Overview

rules_tf2 uses a single configuration file (`versions.json`) and Bazel module extensions to download and manage all tools and providers.

## versions.json

`versions.json` is the central configuration file. It defines versions for all tools and providers in one place.

```json
{
  "providers": {
    "hashicorp/aws": ["5.40.0"],
    "hashicorp/random": ["3.6.0"]
  },
  "tools": {
    "terraform": "1.7.0",
    "tflint": "0.50.0",
    "terraform-docs": "0.17.0"
  },
  "tflint_plugins": {
    "aws": "0.27.0",
    "azurerm": "0.25.0"
  }
}
```

### providers

Maps provider names to version arrays. The format is `namespace/name` (e.g., `hashicorp/aws`).

Multiple versions can be specified when you need different major versions:

```json
"hashicorp/aws": ["5.40.0", "6.0.0"]
```

These become aliases `aws_5` and `aws_6` in `@tf_provider_registry`.

### tools

Specifies versions for Terraform, TFLint, and terraform-docs.

### tflint_plugins

Specifies versions for TFLint plugins. Only include plugins you actually use—they're downloaded on demand.

## Module Extensions

rules_tf2 uses Bazel module extensions (bzlmod) to load configuration. These are declared in your `MODULE.bazel` file.

### tf_providers

Downloads and registers Terraform providers:

```starlark
tf_providers = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_providers")
tf_providers.download(
    versions_file = "path/to/versions.json",
    lock_file = "path/to/provider_locks.json",
)
use_repo(tf_providers, "tf_provider_registry")
```

This reads provider versions, verifies hashes against `provider_locks.json`, and creates `@tf_provider_registry`.

### tf_tools

Downloads tools and TFLint plugins:

```starlark
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")
tf_tools.from_versions_json(versions_file = "path/to/versions.json")
use_repo(tf_tools, "tf_tool_registry", "tflint_plugin_registry")
```

This creates:
- `@tf_tool_registry` - Terraform, TFLint, terraform-docs binaries
- `@tflint_plugin_registry` - TFLint plugins

## Tool Downloads

Tools are downloaded per-platform (linux/darwin, amd64/arm64) during Bazel's analysis phase.

The `tf_tool_registry` provides aliases:
- `@tf_tool_registry//:terraform`
- `@tf_tool_registry//:tflint`
- `@tf_tool_registry//:terraform-docs`

TFLint plugins are available via `@tflint_plugin_registry//:aws`, etc.

> The tf2 plugin is built from source rather than downloaded.

## Updating Versions

1. Edit `versions.json` with new versions
2. Regenerate `provider_locks.json` (hashes for the new versions)
3. Run `bazel test //...` to verify everything works

Change one file, rebuild, verify.

## See Also

- [Providers](providers.md) - Provider caching and management
- [Linting](linting.md) - How TFLint uses these tools
