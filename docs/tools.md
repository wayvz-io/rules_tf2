# Tool Installation

Rules_tf2 automatically downloads and manages Terraform tools (terraform, tflint, terraform-docs) as part of the build process. This eliminates the need for external package managers or manual tool installation.

## Configuration

Add the `tf_tools` module extension to your `MODULE.bazel`:

```starlark
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")

tf_tools.configure(
    terraform_version = "1.12.2",
    tflint_version = "0.54.0",
    terraform_docs_version = "0.20.0",
)

use_repo(tf_tools, "tf_tool_registry")
```

## Implementation

The `tf_tools` module extension:

1. Downloads platform-specific binaries (linux/darwin, amd64/arm64) from official releases
2. Creates individual tool repositories (`terraform_tool`, `tflint_tool`, `terraform_docs_tool`)
3. Provides a central registry (`tf_tool_registry`) with aliases for tool access

Tool binaries are cached per version and reused across builds. The extension automatically detects the host platform and downloads the appropriate binary.

## Usage in Rules

Rules that use these tools include a `_tools` attribute referencing the tool registry:

```starlark
attrs = {
    "_tools": attr.label(
        default = "@tf_tool_registry//:all",
        allow_files = True,
    ),
}
```

Tool paths are resolved at runtime using repository-aware path detection to handle both root module and external dependency scenarios.

## Supported Platforms

- Linux: amd64, arm64
- macOS (Darwin): amd64, arm64

Binary downloads use official release channels:
- Terraform: HashiCorp releases
- TFLint: GitHub releases  
- Terraform-docs: GitHub releases