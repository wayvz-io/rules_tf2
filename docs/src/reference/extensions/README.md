# Module Extensions

Bazel module extensions for configuring rules_tf2 in `MODULE.bazel`. Each reads a
`versions.json` and registers the repositories your modules depend on.

## Overview

| Extension | Provides | Description |
|-----------|----------|-------------|
| [tf_providers](tf-providers.md) | `tf_provider_registry` | Downloads and registers Terraform providers |
| [tf_tools](tf-tools.md) | `tf_tool_registry`, `tflint_plugin_registry` | Downloads terraform, tflint (+ plugins), terraform-docs, opa, sentinel |
| [tf_modules](tf-modules.md) | `tf_module_registry` | Downloads external Terraform modules (Git + registry) |
| [tf_agent_base](tf-agent-base.md) | `tfc_agent_base*` | Pulls the TFC agent base image for [tfc_agent_image](../cloud/tfc-agent-image.md) |

For how to wire these up and the `versions.json` schema, see the
[Add or update a provider](../../guides/add-a-provider.md) and
[Use an external module](../../guides/use-an-external-module.md) guides, and the
[Versioning](../../explanation/versioning/) explanation.
