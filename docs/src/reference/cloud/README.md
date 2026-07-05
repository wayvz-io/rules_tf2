# Cloud Integration

Integration with Terraform Cloud (HCP Terraform) and Terraform Enterprise (TFE).

These rules cover the three TFC/TFE touchpoints: running plans/applies against a
workspace, publishing modules to the private module registry, and building agent
images.

| Rule | Description |
|------|-------------|
| [tfc_workspace](tfc-workspace.md) | Runner targets wired to a TFC/TFE workspace (remote plan/apply) |
| [tfc_publish_registry](tfc-publish-registry.md) | Publish a module to the TFC/TFE private module registry |
| [tfc_agent_image](tfc-agent-image.md) | Build a TFC agent image with providers baked in |

## tfc_workspace

Creates runner targets pre-configured for a Terraform Cloud workspace:

```starlark
tfc_workspace(
    name = "prod",
    module = ":my_module",
    workspace_name = "my-workspace-prod",
    organization = "my-org",
)
```

This generates:
- `:prod` — main runner for any command
- `:prod_validate` — local validation
- `:prod_tfc_plan` — remote plan on TFC
- `:prod_tfc_apply` — remote apply on TFC

```bash
bazel run //:prod_tfc_plan     # remote plan on Terraform Cloud
bazel run //:prod_tfc_apply    # remote apply
```

## tfc_publish_registry

Publishes a module to the TFC/TFE **private** module registry (authenticated
with `TFE_TOKEN`):

```starlark
tfc_publish_registry(
    name = "publish",
    module = ":my_module",
    organization = "my-org",
    module_name = "my-terraform-module",
    provider = "aws",
)
```

```bash
TFE_TOKEN=xxx bazel run //:publish
```

## tfc_agent_image

Builds a custom TFC agent OCI image with providers **pre-bundled**.

**Use case:** ephemeral Terraform Cloud agents normally download their providers
on every cold start. Baking the providers into the agent image removes that
per-run download, so agents boot and start planning faster.

```starlark
tfc_agent_image(
    name = "my_agent",
    providers = ["@tf_provider_registry//:aws_6"],
    repository = "my-org/tfc-agent",
)
```

This generates:
- `:my_agent` — OCI image index (single-arch amd64 by default; multi-arch only when multiple `platforms` are given)
- `:my_agent_push` — push to the registry

```bash
bazel build //:my_agent        # build the agent image
bazel run  //:my_agent_push    # push to the container registry
```

See [tfc_agent_image](tfc-agent-image.md) for full documentation.
