# Module Extensions

Bazel module extensions for MODULE.bazel configuration.

## Overview

| Extension | Provided Repos | Description |
|-----------|----------------|-------------|
| [tf_providers](#tf_providers) | `tf_provider_registry` | Provider download and registry management |
| [tf_tools](#tf_tools) | `tf_tool_registry`, `tflint_plugin_registry` | Tool download (terraform, tflint, terraform-docs, opa, sentinel) |
| [tf_modules](#tf_modules) | `tf_module_registry` | External Terraform module management (Git + registry) |
| [tf_agent_base](#tf_agent_base) | `tfc_agent_base`, `tfc_agent_base_linux_amd64`, `tfc_agent_base_linux_arm64` | TFC agent base image management |

## tf_providers

Configure provider downloads in your MODULE.bazel:

```starlark
tf_providers = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_providers")
tf_providers.download(
    versions_file = "path/to/versions.json",
)
use_repo(tf_providers, "tf_provider_registry")
```

Provider hashes are auto-generated and cached in `MODULE.bazel.lock` via extension facts
(requires Bazel 8.5+).

## tf_tools

Configure tool versions. The usual path reads every version from `versions.json`:

```starlark
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")
tf_tools.from_versions_json(versions_file = "path/to/versions.json")
use_repo(tf_tools, "tf_tool_registry", "tflint_plugin_registry")
```

### Tags

| Tag | Purpose |
|-----|---------|
| `from_versions_json(versions_file)` | Read all tool and tflint-plugin versions from a `versions.json`. |
| `configure(terraform_version, tflint_version, terraform_docs_version)` | Set those three versions explicitly (overrides `versions.json`). |
| `tflint_plugin(name, version)` | Add a single TFLint plugin explicitly. |

Explicit configuration instead of (or overriding) `versions.json`:

```starlark
tf_tools.configure(
    terraform_version = "1.13.2",
    tflint_version = "0.59.1",
    terraform_docs_version = "0.20.0",
)
tf_tools.tflint_plugin(name = "aws", version = "0.42.0")
tf_tools.tflint_plugin(name = "azurerm", version = "0.29.0")
```

## tf_modules

Configure external Terraform modules (from Git repositories and the Terraform Module
Registry) declared in versions.json:

```starlark
tf_modules = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_modules")
tf_modules.download(
    versions_file = "path/to/versions.json",
)
use_repo(tf_modules, "tf_module_registry")
```

Modules are declared under a `modules` key in versions.json (with `registry` and `git`
sub-sections) and referenced as `@tf_module_registry//:vpc_aws_5`.

## versions.json Format

```json
{
  "tools": {
    "terraform": "1.14.1",
    "tflint": "0.60.0",
    "terraform-docs": "0.20.0",
    "opa": "1.4.2",
    "sentinel": "0.40.0"
  },
  "providers": {
    "hashicorp/aws": ["5.0.0"],
    "hashicorp/random": ["3.0.0"]
  },
  "tflint_plugins": {
    "aws": "0.30.0"
  }
}
```

## tf_agent_base

Configure TFC agent base image for [tfc_agent_image](../cloud/tfc-agent-image.md):

```starlark
tf_agent_base = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_agent_base")
tf_agent_base.from_versions_json(
    versions_file = "path/to/versions.json",
)
use_repo(tf_agent_base, "tfc_agent_base", "tfc_agent_base_linux_amd64", "tfc_agent_base_linux_arm64")
```

The extension reads `tfc-agent` version from versions.json and pulls the appropriate `hashicorp/tfc-agent` Docker image for both linux/amd64 and linux/arm64 platforms.

### versions.json

```json
{
  "tools": {
    "tfc-agent": "1.17.0"
  }
}
```
