# Tool Installation

Rules_tf2 automatically downloads and manages Terraform tools (terraform, tflint, terraform-docs) and TFLint plugins as part of the build process. This eliminates the need for external package managers or manual tool installation.

## Configuration

Add the `tf_tools` module extension to your `MODULE.bazel`:

```starlark
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")

tf_tools.configure(
    terraform_version = "1.13.2",
    tflint_version = "0.59.1",
    terraform_docs_version = "0.20.0",
)

use_repo(tf_tools, "tf_tool_registry")
```

## TFLint Plugin Support

TFLint plugins can be configured to extend linting capabilities for specific cloud providers:

```starlark
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")

tf_tools.configure(
    terraform_version = "1.13.2",
    tflint_version = "0.59.1",
    terraform_docs_version = "0.20.0",
)

# Configure TFLint plugins
tf_tools.tflint_plugin(
    name = "aws",
    version = "0.42.0",
)

tf_tools.tflint_plugin(
    name = "azurerm",
    version = "0.29.0",
)

tf_tools.tflint_plugin(
    name = "google",
    version = "0.35.0",
)

use_repo(tf_tools, "tf_tool_registry", "tflint_plugin_registry")
```

### Supported TFLint Plugins

- **aws**: AWS provider-specific rules (terraform-linters/tflint-ruleset-aws)
- **azurerm**: Azure Resource Manager provider rules (terraform-linters/tflint-ruleset-azurerm)
- **google**: Google Cloud Platform provider rules (terraform-linters/tflint-ruleset-google)
- **opa**: Open Policy Agent custom rule engine (terraform-linters/tflint-ruleset-opa)

## Implementation

The `tf_tools` module extension:

1. Downloads platform-specific binaries (linux/darwin, amd64/arm64) from official releases
2. Creates individual tool repositories (`terraform_tool`, `tflint_tool`, `terraform_docs_tool`)
3. Downloads TFLint plugin binaries when configured (`tflint_plugin_aws`, `tflint_plugin_azurerm`, etc.)
4. Provides central registries (`tf_tool_registry`, `tflint_plugin_registry`) with aliases for tool access

Tool and plugin binaries are cached per version and reused across builds. The extension automatically detects the host platform and downloads the appropriate binary.

### Plugin Installation

When TFLint plugins are configured, the system:

1. Downloads platform-specific plugin binaries from GitHub releases
2. Creates individual plugin repositories for each configured plugin
3. Makes plugins available through the `tflint_plugin_registry`
4. Automatically configures plugin paths during TFLint execution

Plugins are installed in the standard TFLint plugin directory structure and loaded automatically when TFLint runs.

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

For rules that need TFLint plugins, include the plugin registry as well:

```starlark
attrs = {
    "plugins": attr.label_list(
        allow_files = True,
        doc = "TFLint plugin binaries",
    ),
    "_tools": attr.label(
        default = "@tf_tool_registry//:all",
        allow_files = True,
    ),
}
```

Tool paths are resolved at runtime using repository-aware path detection to handle both root module and external dependency scenarios. Plugin paths are automatically configured in the TFLint working directory.

## Supported Platforms

- Linux: amd64, arm64
- macOS (Darwin): amd64, arm64

Binary downloads use official release channels:
- Terraform: HashiCorp releases
- TFLint: GitHub releases  
- Terraform-docs: GitHub releases