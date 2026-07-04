# tfc_agent_image

Build custom TFC agent Docker images with bundled Terraform providers.

```starlark
load("@rules_tf2//tf2:def.bzl", "tfc_agent_image")

tfc_agent_image(
    name = "my_agent",
    providers = ["@tf_provider_registry//:aws_6"],
    repository = "my-org/tfc-agent",
)
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | Yes | Target name for the image |
| `providers` | list | No | Provider aliases or labels to include |
| `module` | label | No | tf_module to extract providers from |
| `platforms` | list | No | Target platforms (default: `["linux_amd64"]`) |
| `include_terraform` | bool | No | Include terraform binary (default: `True`) |
| `registry` | string | No | OCI registry hostname (default: `ghcr.io`) |
| `repository` | string | No | Repository path for push target |
| `tag` | string | No | Image tag (default: `latest`) |
| `tags` | list | No | Bazel tags for targets |
| `visibility` | list | No | Target visibility |

## Provider Selection

Three modes for selecting which providers to bundle:

| Mode | When | Description |
|------|------|-------------|
| All providers | Neither `providers` nor `module` specified | Bundles all providers from `@tf_provider_registry` |
| Explicit list | `providers` specified | Bundles only the listed providers |
| Module extraction | `module` specified | Extracts providers from the tf_module's dependencies |

## Generated Targets

| Target | Description |
|--------|-------------|
| `:{name}` | OCI image index (single-arch by default; multi-arch only when multiple `platforms` are given) |
| `:{name}_linux_amd64` | AMD64 platform image (created by the default `platforms`) |
| `:{name}_linux_arm64` | ARM64 platform image (only when `linux_arm64` is added to `platforms`) |
| `:{name}_push` | Push target (if `repository` specified) |
| `:{name}_terraformrc` | Generated .terraformrc file |

> **Note:** `platforms` defaults to `["linux_amd64"]`, so only the amd64 image and a
> single-arch index are created. Add `"linux_arm64"` to `platforms` to also build the
> arm64 image, but note that the upstream `hashicorp/tfc-agent` base image often has no
> arm64 manifest for a given version, so arm64 is opt-in and untested.

## Examples

### All providers

```starlark
tfc_agent_image(
    name = "full_agent",
    repository = "my-org/tfc-agent-full",
)
```

### Specific providers

```starlark
tfc_agent_image(
    name = "aws_agent",
    providers = [
        "@tf_provider_registry//:aws_6",
        "@tf_provider_registry//:random_3",
    ],
    repository = "my-org/tfc-agent-aws",
)
```

### From tf_module

```starlark
tfc_agent_image(
    name = "module_agent",
    module = "//iac/modules/vpc:tf_module",
    repository = "my-org/tfc-agent-vpc",
)
```

### Single platform

```starlark
tfc_agent_image(
    name = "amd64_only",
    platforms = ["linux_amd64"],
    providers = ["@tf_provider_registry//:aws_6"],
)
```

## Usage

Build the image:
```bash
bazel build //:my_agent
```

Push to registry:
```bash
bazel run //:my_agent_push
```

## Image Contents

Each image contains:

| Path | Contents |
|------|----------|
| `/usr/local/bin/terraform` | Terraform binary |
| `/etc/terraform/plugins/` | Provider filesystem mirror |
| `/etc/terraform/.terraformrc` | Provider mirror configuration |

The `.terraformrc` configures Terraform to use the bundled filesystem mirror, eliminating provider downloads at runtime.

## Requirements

### MODULE.bazel

```starlark
# Required extensions
tf_agent_base = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_agent_base")
tf_agent_base.from_versions_json(
    versions_file = "//path/to:versions.json",
)
use_repo(tf_agent_base, "tfc_agent_base", "tfc_agent_base_linux_amd64", "tfc_agent_base_linux_arm64")
```

### versions.json

Include `tfc-agent` in the tools section:

```json
{
  "tools": {
    "tfc-agent": "1.17.0"
  }
}
```

See [Module Extensions](../extensions/README.md) for full extension configuration.
