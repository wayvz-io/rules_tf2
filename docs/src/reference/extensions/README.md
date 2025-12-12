# Module Extensions

Bazel module extensions for MODULE.bazel configuration.

## Overview

| Extension | Description |
|-----------|-------------|
| [tf_providers](tf-providers.md) | Provider download and registry management |
| [tf_tools](tf-tools.md) | Tool download (terraform, tflint, terraform-docs) |

## tf_providers

Configure provider downloads in your MODULE.bazel:

```starlark
tf_providers = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_providers")
tf_providers.download(
    versions_file = "path/to/versions.json",
    lock_file = "path/to/provider_locks.json",
)
use_repo(tf_providers, "tf_provider_registry")
```

## tf_tools

Configure tool versions:

```starlark
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")
tf_tools.from_versions_json(versions_file = "path/to/versions.json")
use_repo(tf_tools, "tf_tool_registry", "tflint_plugin_registry")
```

## versions.json Format

```json
{
  "tools": {
    "terraform": "1.14.1",
    "tflint": "0.60.0",
    "terraform-docs": "0.20.0"
  },
  "providers": {
    "aws": "5.0.0",
    "random": "3.0.0"
  },
  "tflint_plugins": {
    "aws": "0.30.0"
  }
}
```
