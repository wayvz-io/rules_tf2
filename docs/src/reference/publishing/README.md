# Publishing

Module publishing to registries.

## Overview

| Rule | Description |
|------|-------------|
| [tf_module_publish](tf-module-publish.md) | Publish to Terraform Registry (HCP/TFE) |
| [tf_module_push_oci](tf-module-push-oci.md) | Push to OCI registries |

## Terraform Registry

Publish modules to HCP Terraform or Terraform Enterprise:

```starlark
tf_module_publish(
    name = "publish",
    module = ":my_module",
    organization = "my-org",
    namespace = "my-namespace",
)
```

```bash
bazel run //:publish
```

## OCI Registry

Push modules to OCI-compatible registries (GitHub Container Registry, etc.):

```starlark
tf_module_push_oci(
    name = "push_oci",
    srcs = [":my_module"],
    image = "ghcr.io/my-org/my-module",
    registry = "ghcr.io",
)
```

```bash
bazel run //:push_oci
```

OCI publishing uses ORAS with Flux-compatible media types and metadata.
