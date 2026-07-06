# tfc_agent_image

Build a custom TFC agent OCI image with Terraform providers baked in, so
ephemeral agents don't re-download providers on cold start.

> For the end-to-end how-to (MODULE.bazel setup, build & push), see
> [Bake providers into an ephemeral agent image](../../guides/terraform-cloud.md).

```starlark
load("@rules_tf2//tf2:def.bzl", "tfc_agent_image")

tfc_agent_image(
    name = "aws_agent",
    providers = ["@tf_provider_registry//:aws_6"],
    repository = "my-org/tfc-agent-aws",
)
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Target name for the image |
| `providers` | list | No | Provider aliases (`["aws_6"]`) or labels (`["@tf_provider_registry//:aws_6"]`). Mutually exclusive with `module`; if both omitted, all providers are bundled |
| `module` | label | No | `tf_module` to extract providers from. Mutually exclusive with `providers` |
| `platforms` | list | No | Target platforms (default `["linux_amd64"]`). `linux_arm64` is opt-in and untested — the upstream `hashicorp/tfc-agent` base often has no arm64 manifest |
| `include_terraform` | bool | No | Include the terraform binary (default `True`) |
| `registry` | string | No | OCI registry hostname (default `ghcr.io`) |
| `repository` | string | No | Repository path for the push target |
| `tag` | string | No | Image tag (default `latest`) |
| `tags` | list | No | Bazel tags for the generated targets |
| `visibility` | list | No | Target visibility |

## Generated targets

| Target | Description |
|--------|-------------|
| `:{name}` | OCI image index (single-arch unless multiple `platforms` given) |
| `:{name}_linux_amd64` | amd64 platform image |
| `:{name}_linux_arm64` | arm64 platform image (only if `linux_arm64` in `platforms`) |
| `:{name}_push` | Push target (only when `repository` is set) |
| `:{name}_terraformrc` | Generated `.terraformrc` |

## See also

- [Bake providers into an ephemeral agent image](../../guides/terraform-cloud.md) — the how-to
- [Module Extensions](../extensions/) — the required `tf_agent_base` extension
