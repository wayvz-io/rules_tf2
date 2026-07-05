# Flux (GitOps)

Publishing Terraform modules as OCI artifacts for a Flux-based GitOps workflow.

Unlike the [Terraform Cloud](../cloud/README.md) path — where TFC/TFE runs the
plan and apply — the Flux path packages a module as an **OCI artifact** that Flux
pulls and a Terraform/OpenTofu controller reconciles against a cluster.

| Rule | Description |
|------|-------------|
| [tf_publish_oci_flux](tf-publish-oci-flux.md) | Push a module as a Flux-compatible OCI artifact |

## tf_publish_oci_flux

Pushes the packaged module to an OCI registry using the CNCF Flux media types,
with the `org.opencontainers.image.source` / `revision` annotations a GitOps
controller watches:

```starlark
tf_publish_oci_flux(
    name = "push_oci",
    module = ":my_module",
    stack_name = "aws/hub",
)
```

```bash
bazel run //:push_oci
```

**Use case:** you keep infrastructure in Git and let Flux drive it. A Flux
`OCIRepository` watches the pushed artifact; when a new revision appears, a
Terraform/OpenTofu controller applies it — no direct backend access from CI.
The push uses ORAS with Flux content/config media types and Flux-compatible OCI
annotations, so the artifact is consumable by a standard Flux source controller.
