# Cloud Integration

Terraform Cloud and Terraform Enterprise integration.

## Overview

| Rule | Description |
|------|-------------|
| [tf_cloud_configuration](tf-cloud-configuration.md) | Create multiple TFC runner targets |
| [tf_cloud_workspace](tf-cloud-workspace.md) | Backward compatibility alias |

## tf_cloud_configuration

Creates runner targets pre-configured for Terraform Cloud workspaces:

```starlark
tf_cloud_configuration(
    name = "prod",
    module = ":my_module",
    workspace_name = "my-workspace-prod",
    organization = "my-org",
)
```

This generates:
- `:prod` - Main runner for any command
- `:prod_validate` - Local validation
- `:prod_tfc_plan` - Remote plan on TFC
- `:prod_tfc_apply` - Remote apply on TFC

## Usage

```bash
# Run a plan on Terraform Cloud
bazel run //:prod_tfc_plan

# Apply changes
bazel run //:prod_tfc_apply
```
