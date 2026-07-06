# Tool Versioning

The `tools` section of `versions.json` specifies versions for binaries:

```json
{
  "tools": {
    "terraform": "1.7.0",
    "tflint": "0.50.0",
    "terraform-docs": "0.17.0",
    "opa": "1.4.2",
    "sentinel": "0.40.0",
    "tfc-agent": "1.17.0"
  }
}
```

## Download Process

The `tf_tools` extension downloads platform-specific binaries (linux/darwin, amd64/arm64) during Bazel's analysis phase.

Downloads come from:
- **Terraform**: `releases.hashicorp.com`
- **TFLint**: GitHub releases (`terraform-linters/tflint`)
- **terraform-docs**: GitHub releases (`terraform-docs/terraform-docs`)
- **OPA**: GitHub releases (`open-policy-agent/opa`)
- **Sentinel**: `releases.hashicorp.com`
- **tfc-agent**: Docker Hub (`hashicorp/tfc-agent`) - via `tf_agent_base` extension

Each binary is verified against the publisher's checksums and the resolved
sha256 is locked in `MODULE.bazel.lock` — see [Download integrity](../hermeticity.md#download-integrity).

## Registry Aliases

Tools are available through `@tf_tool_registry`:

```starlark
@tf_tool_registry//:terraform
@tf_tool_registry//:tflint
@tf_tool_registry//:terraform-docs
@tf_tool_registry//:opa
@tf_tool_registry//:sentinel
```

These are `sh_binary` targets that resolve to the correct platform binary.

## Version Selection

If a tool version isn't specified in `versions.json`, the extension uses a built-in default. Explicit versions are recommended for reproducibility.

## Pinning Versions

Pin versions to ensure consistent builds across machines and CI:

```json
{
  "tools": {
    "terraform": "1.7.0"
  }
}
```

Without pinning, different team members might get different tool versions depending on when they last updated their cache.

## TFC Agent

The `tfc-agent` version is used by the `tf_agent_base` module extension to pull the Terraform Cloud agent Docker image. This is separate from `tf_tools` because it downloads an OCI image rather than a binary.

```starlark
tf_agent_base = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_agent_base")
tf_agent_base.from_versions_json(versions_file = "path/to/versions.json")
use_repo(tf_agent_base, "tfc_agent_base", "tfc_agent_base_linux_amd64", "tfc_agent_base_linux_arm64")
```

See [tfc_agent_image](../../reference/cloud/tfc-agent-image.md) for building custom agent images.
