# Tool Versioning

The `tools` section of `versions.json` specifies versions for three binaries:

```json
{
  "tools": {
    "terraform": "1.7.0",
    "tflint": "0.50.0",
    "terraform-docs": "0.17.0"
  }
}
```

## Download Process

The `tf_tools` extension downloads platform-specific binaries (linux/darwin, amd64/arm64) during Bazel's analysis phase.

Downloads come from:
- **Terraform**: `releases.hashicorp.com`
- **TFLint**: GitHub releases (`terraform-linters/tflint`)
- **terraform-docs**: GitHub releases (`terraform-docs/terraform-docs`)

## Registry Aliases

Tools are available through `@tf_tool_registry`:

```starlark
@tf_tool_registry//:terraform
@tf_tool_registry//:tflint
@tf_tool_registry//:terraform-docs
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
