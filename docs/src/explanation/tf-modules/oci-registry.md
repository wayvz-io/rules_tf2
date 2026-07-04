# OCI Registry Publishing

rules_tf2 can publish modules as OCI artifacts to container registries.

## Why OCI?

OCI registries (GitHub Container Registry, AWS ECR, Azure ACR) provide:

- Existing infrastructure—no separate module registry needed
- Standard authentication mechanisms
- GitOps integration with tools like Flux

## How It Works

Modules are packaged as OCI artifacts using ORAS (OCI Registry As Storage). This is the same mechanism Helm charts and Flux use for non-container artifacts.

## tf_publish_oci

```starlark
tf_publish_oci(
    name = "push_oci",
    module = ":my_module",
    stack_name = "vpc",
)
```

Run with:

```bash
bazel run //path/to:push_oci
```

## Authentication

Uses standard container registry authentication:

- Environment variables (`GITHUB_TOKEN`, `AWS_ACCESS_KEY_ID`, etc.)
- Docker config (`~/.docker/config.json`)
- Credential helpers

## Flux Integration

Published modules include OCI annotations for Flux source controller:

```yaml
annotations:
  org.opencontainers.image.source: https://github.com/org/repo
  org.opencontainers.image.revision: abc123
```

Flux can watch for module updates and trigger reconciliation automatically.

## Consuming OCI Modules

Reference OCI-published modules in Terraform:

```hcl
module "vpc" {
  source  = "oci://ghcr.io/my-org/terraform-modules/vpc"
  version = "1.0.0"
}
```

Requires Terraform 1.14+ for native OCI module source support.

## See Also

- [tf_publish_oci Reference](../../reference/publishing/tf-publish-oci.md)
