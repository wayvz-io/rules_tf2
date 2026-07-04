# Publishing

Module publishing to registries.

## Overview

| Rule | Description |
|------|-------------|
| [tf_publish_registry](tf-publish-registry.md) | Publish to Terraform Registry (HCP/TFE) |
| [tf_publish_oci](tf-publish-oci.md) | Push to OCI registries |

## Terraform Registry

Publish modules to HCP Terraform or Terraform Enterprise:

```starlark
tf_publish_registry(
    name = "publish",
    module = ":my_module",
    organization = "my-org",
    module_name = "my-terraform-module",
    provider = "aws",
    # namespace = "my-namespace",  # optional, defaults to organization
)
```

```bash
bazel run //:publish
```

## OCI Registry

Push modules to OCI-compatible registries (GitHub Container Registry, etc.):

```starlark
tf_publish_oci(
    name = "push_oci",
    module = ":my_module",
    stack_name = "my-module",
)
```

```bash
bazel run //:push_oci
```

OCI publishing uses ORAS with Flux-compatible media types and metadata.
