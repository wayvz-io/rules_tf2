# About Versioning

rules_tf2 manages external dependencies through a single `versions.json` file. This centralizes version control for:

- **Providers** - Terraform providers (aws, azurerm, google, etc.)
- **Tools** - Terraform, TFLint, terraform-docs binaries
- **TFLint Plugins** - Provider-specific linting rulesets

```json
{
  "providers": {
    "hashicorp/aws": ["5.40.0", "6.0.0"],
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

Bazel module extensions read this file and download everything during analysis. Change versions in one place, rebuild, and the entire workspace updates.

## Module Extensions

Two extensions in `MODULE.bazel` load the configuration:

```starlark
# Providers
tf_providers = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_providers")
tf_providers.download(
    versions_file = "path/to/versions.json",
    lock_file = "path/to/provider_locks.json",
)
use_repo(tf_providers, "tf_provider_registry")

# Tools
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")
tf_tools.from_versions_json(versions_file = "path/to/versions.json")
use_repo(tf_tools, "tf_tool_registry", "tflint_plugin_registry")
```

`tf_providers` creates `@tf_provider_registry` with provider aliases. `tf_tools` creates `@tf_tool_registry` and `@tflint_plugin_registry`.

## Updating Versions

1. Edit `versions.json` with new versions
2. Regenerate `provider_locks.json` for new provider hashes
3. Run `bazel test //...` to verify

See [Auto Updates](auto-updates.md) for scripts that automate this workflow.
