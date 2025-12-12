# About Publishing System

## Overview

rules_tf2 supports publishing Terraform modules to two registry types: Terraform Registry (HCP Terraform / TFE) and OCI registries.

## What Gets Published

When you publish a module, rules_tf2 creates a self-contained bundle:

- **Nested modules**: Child modules are included. Consumers get everything in one artifact.
- **Generated lockfile**: The `.terraform.lock.hcl` is included, so consumers get reproducible provider versions.
- **Only Bazel-exposed files**: The bundle contains only files explicitly declared in `srcs`. No stray files, no build artifacts—just what Bazel knows about.

## Terraform Registry Publishing

Modules are packaged as tarballs and uploaded to the registry API. This is the standard approach for Terraform Cloud or Terraform Enterprise.

Authentication uses `TFE_TOKEN` environment variable or Terraform CLI credentials.

## OCI Registry Publishing

Modules are packaged as OCI artifacts and pushed using ORAS to container registries (GitHub Container Registry, AWS ECR, etc.).

> ORAS (OCI Registry As Storage) is the standard for pushing non-container artifacts to OCI registries—it's what Helm and Flux use.

### Flux Integration

Published modules include metadata for Flux source controller:

```yaml
annotations:
  org.opencontainers.image.source: https://github.com/org/repo
  org.opencontainers.image.revision: abc123
```

This enables GitOps workflows where Flux automatically detects module updates.

Authentication uses standard container registry mechanisms: environment variables, Docker config, or credential helpers.

## Terraform Cloud

`tf_cloud_configuration` creates runner targets that interact with Terraform Cloud (or Terraform Enterprise) workspaces.

### What tf_cloud_configuration Creates

From a single declaration, you get multiple targets:

- `name` - Main runner (can run any terraform command)
- `name_validate` - Local validation without backend
- `name_tfc_plan` - Run plan against the TFC workspace
- `name_tfc_apply` - Run apply against the TFC workspace

### Backend Generation

By default (`auto_backend = True`), rules_tf2 generates the cloud backend configuration automatically:

```hcl
terraform {
  cloud {
    organization = "your-org"
    workspaces {
      name = "your-workspace"
    }
  }
}
```

Your module doesn't need backend configuration in its `.tf` files—it's injected at runtime.

### Local vs Remote Execution

`*_validate` runs locally without a backend. `*_tfc_plan` and `*_tfc_apply` connect to Terraform Cloud.

## Planned Export Features

### Provider Library Exports

We may add the ability to export providers as a standalone bundle. This would let you build runner containers with pre-cached providers, or pass providers to tools like Terragrunt that manage their own caching.

### Policy Exports

- **Sentinel** (coming soon)
- **OPA** (coming soon)

### Terraform Stacks

Terraform Stacks will be exportable to file directories (coming soon).

## See Also

- [Architecture](architecture.md)
