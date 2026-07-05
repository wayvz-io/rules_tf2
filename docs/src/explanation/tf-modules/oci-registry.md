# OCI Registry Publishing

rules_tf2 can publish modules as OCI artifacts to container registries.

## Why OCI?

OCI registries (GitHub Container Registry, AWS ECR, Azure ACR) provide:

- Existing infrastructure—no separate module registry needed
- Standard authentication mechanisms
- GitOps integration with tools like Flux

## How It Works

Modules are packaged as OCI artifacts using ORAS (OCI Registry As Storage). This is the same mechanism Helm charts and Flux use for non-container artifacts.

## tf_publish_oci_flux

```starlark
tf_publish_oci_flux(
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

The push follows the ambient OCI credential chain, the same model `rules_oci`
uses. By default the generated push script does not log in at all: ORAS resolves
credentials from the Docker config chain (`~/.docker/config.json` plus any
configured credential helpers), so whatever populated that config — `docker
login`, `oras login`, `docker/login-action` in CI, or a cloud credential helper
for ECR/ACR/GCR — is honoured transparently.

For self-contained targets you can instead have the script log in explicitly by
setting the `OCI_USERNAME`/`OCI_PASSWORD` environment variables (the names are
configurable per target via `username_env`/`password_env`). When both are set the
script performs an `oras login`; otherwise it falls through to the ambient
credentials. This keeps the rules registry-agnostic and free of any dependency on
the GitHub CLI. See [Publish a module](../../guides/publish-a-module.md) for the
step-by-step flow.

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

- [tf_publish_oci_flux Reference](../../reference/flux/tf-publish-oci-flux.md)
