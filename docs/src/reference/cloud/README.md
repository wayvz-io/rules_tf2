# Cloud Integration

Terraform Cloud and Terraform Enterprise integration.

## Overview

| Rule | Description |
|------|-------------|
| [tf_cloud_workspace](tf-cloud-workspace.md) | Create multiple TFC runner targets |
| [tfc_agent_image](tfc-agent-image.md) | Build custom TFC agent Docker images |

## tf_cloud_workspace

Creates runner targets pre-configured for Terraform Cloud workspaces:

```starlark
tf_cloud_workspace(
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

## tfc_agent_image

Build custom TFC agent Docker images with bundled providers:

```starlark
tfc_agent_image(
    name = "my_agent",
    providers = ["@tf_provider_registry//:aws_6"],
    repository = "my-org/tfc-agent",
)
```

This generates:
- `:my_agent` - Multi-arch OCI image
- `:my_agent_push` - Push to registry

```bash
# Build the agent image
bazel build //:my_agent

# Push to container registry
bazel run //:my_agent_push
```

See [tfc_agent_image](tfc-agent-image.md) for full documentation.
