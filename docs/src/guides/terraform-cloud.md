# Run against Terraform Cloud

Drive remote plans/applies on a Terraform Cloud (HCP) or Enterprise workspace,
and optionally build agent images with providers baked in.

## Prerequisites

- A working `tf_module` — see [Create and test a module](create-and-test-a-module.md).

## Remote plan / apply on a workspace

1. Declare `tfc_workspace` (`organization` is required):

   ```starlark
   load("@rules_tf2//tf2:def.bzl", "tfc_workspace")

   tfc_workspace(
       name = "prod",
       module = ":my_module",
       workspace_name = "my-workspace-prod",
       organization = "my-org",
       # tfe_host = "tfe.my-company.com",  # defaults to app.terraform.io
   )
   ```

   This wraps [`tf_runner`](run-terraform.md) and generates `:prod` (any
   command), `:prod_validate` (local, `-backend=false`), `:prod_tfc_plan`, and
   `:prod_tfc_apply`.

2. Run remote operations:

   ```bash
   bazel run //path/to:prod_tfc_plan
   bazel run //path/to:prod_tfc_apply
   ```

   Terraform's cloud backend handles auth (e.g. a `TFE_TOKEN` / credentials the
   backend reads at run time).

## Bake providers into an ephemeral agent image

Ephemeral TFC agents re-download providers on every cold start.
`tfc_agent_image` builds an agent OCI image with the providers pre-bundled, so
agents boot and start planning faster.

1. Add the `tf_agent_base` extension to `MODULE.bazel` and a `tfc-agent` version
   to `versions.json`:

   ```starlark
   tf_agent_base = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_agent_base")
   tf_agent_base.from_versions_json(versions_file = "//path/to:versions.json")
   use_repo(tf_agent_base, "tfc_agent_base", "tfc_agent_base_linux_amd64", "tfc_agent_base_linux_arm64")
   ```

   ```json
   { "tools": { "tfc-agent": "1.17.0" } }
   ```

2. Declare `tfc_agent_image` — bundle specific providers (or extract them from a
   module with `module = ":my_module"`):

   ```starlark
   load("@rules_tf2//tf2:def.bzl", "tfc_agent_image")

   tfc_agent_image(
       name = "my_agent",
       providers = ["@tf_provider_registry//:aws_6"],
       repository = "my-org/tfc-agent",
   )
   ```

3. Build and push (`:name_push` exists only when `repository` is set):

   ```bash
   bazel build //path/to:my_agent
   bazel run  //path/to:my_agent_push
   ```

## See also

- [`tfc_agent_image` reference](../reference/cloud/tfc-agent-image.md) · [Cloud Integration](../reference/cloud/)
- [Hermeticity, CI & CD](../explanation/hermeticity.md) — where plans/applies run vs the hermetic checks
