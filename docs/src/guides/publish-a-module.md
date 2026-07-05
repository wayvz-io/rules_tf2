# Publish a module

Publish a module either to the Terraform Cloud / Enterprise private registry, or
as a Flux-compatible OCI artifact for GitOps. Both package the same hermetic
bundle (sources + nested modules + docs; the generated lockfile is deliberately
excluded).

## Prerequisites

- A working `tf_module` — see [Create and test a module](create-and-test-a-module.md).

## To the TFC/TFE private registry

1. Declare `tfc_publish_registry`:

   ```starlark
   load("@rules_tf2//tf2:def.bzl", "tfc_publish_registry")

   tfc_publish_registry(
       name = "publish",
       module = ":my_module",
       organization = "my-org",
       module_name = "my-terraform-module",
       provider = "aws",
   )
   ```

2. Publish (auth via `TFE_TOKEN`, required):

   ```bash
   TFE_TOKEN=xxx bazel run //path/to:publish
   ```

   The version is auto-computed (current highest + bump). Control the bump with
   `version_increment` (`major`/`minor`/`patch`, default `patch`) or override at
   run time: `-- --version-type minor`, or `-- --version 2.0.0`. Point at TFE
   with the `registry` attribute (defaults to `app.terraform.io`).

## As a Flux OCI artifact (GitOps)

1. Declare `tf_publish_oci_flux`:

   ```starlark
   load("@rules_tf2//tf2:def.bzl", "tf_publish_oci_flux")

   tf_publish_oci_flux(
       name = "push_oci",
       module = ":my_module",
       stack_name = "aws/hub",
   )
   ```

2. Push:

   ```bash
   bazel run //path/to:push_oci
   ```

   Pushes `{registry}/{repository}/tf/{stack_name}:{tag}` (defaults:
   `ghcr.io`, tag `unstable`) via ORAS, with Flux CNCF media types and the
   `org.opencontainers.image.source` / `revision` annotations a Flux
   `OCIRepository` watches. Authentication follows the ambient OCI credential
   chain, like `rules_oci`: ORAS reads `~/.docker/config.json` (plus any
   credential helpers), so a prior `docker login <registry>` / `oras login
   <registry>` — or `docker/login-action` in CI — is enough. Alternatively set
   `OCI_USERNAME`/`OCI_PASSWORD` (or the vars named by `username_env`/`password_env`)
   and the push logs in for you. For `ghcr.io`, that's your GitHub username plus a
   PAT or `GITHUB_TOKEN` — no `gh` CLI required.

## Verification

The registry publish creates/increments the module version in the registry; the
OCI push produces an artifact a Flux source controller can pull.

## See also

- [`tfc_publish_registry`](../reference/cloud/tfc-publish-registry.md) · [Module Registry Publishing](../explanation/tf-modules/module-registry.md)
- [`tf_publish_oci_flux`](../reference/flux/tf-publish-oci-flux.md) · [OCI Registry Publishing](../explanation/tf-modules/oci-registry.md)
