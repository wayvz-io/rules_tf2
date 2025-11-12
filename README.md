# rules_tf2

Bazel rules for managing Terraform infrastructure. These rules have been extracted from an internal repository and are still in alpha - not yet ready for external consumption.

> **Note**: This is an early alpha release. Proper documentation is coming but will take time to develop. Expect breaking changes.

## Status

- **Alpha** - Core functionality works but APIs may change
- **CDK support** - Coming in the future
- **OCI publishing** - Overdue for a rewrite
- **Policy testing** - Sentinel/OPA support for testing workflows coming soon

## Features

- Terraform module and stack management through Bazel
- Terraform Cloud/Enterprise integration
- Provider management with automatic downloading and caching
- Run arbitrary terraform commands through Bazel
- Comprehensive testing (format, lint, validate, docs)
- Tool integration (terraform, tflint, terraform-docs)

## Project Structure

```
tf2/
├── cdktf/             # CDKTF support (future)
├── internal/          # Internal utilities
├── macros/            # Public API macros
├── module/            # Module implementations
├── providers/         # Provider management
├── publish/           # OCI publishing (needs rewrite)
├── testing/           # Test rules
├── tfcloud/           # Terraform Cloud integration
├── tfcore/            # Core Terraform functionality
├── tfdocs/            # terraform-docs integration
├── tflint/            # tflint integration
├── tools/             # Tool management
└── def.bzl            # Public API exports
```

## Quick Start

### 1. Add to MODULE.bazel

```starlark
bazel_dep(name = "rules_tf2", version = "0.0.1")

# Currently requires archive override (not published to BCR yet)
archive_override(
    module_name = "rules_tf2",
    urls = ["https://github.com/yourusername/rules_tf2/archive/refs/tags/v0.0.1.tar.gz"],
    strip_prefix = "rules_tf2-0.0.1",
)

# Configure providers
tf_providers = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_providers")
tf_providers.download(
    providers = {
        "hashicorp/aws": ["6.2.0"],
        "hashicorp/azurerm": ["4.18.0"],
        "hashicorp/google": ["6.17.0"],
    },
)
use_repo(tf_providers, "tf_provider_registry")

# Configure tools
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")
use_repo(tf_tools, "tf_tools")
```

### 2. Define a Terraform Module

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "vpc",
    # Automatically finds all .tf files in the directory
    providers = [
        "@tf_provider_registry//:aws_6",
    ],
)
```

This generates test targets:
- `:vpc_format_test` - Checks formatting
- `:vpc_lint_test` - Runs tflint
- `:vpc_validate_test` - Validates configuration
- `:vpc_doc_test` - Checks documentation

### 3. Run Terraform Commands

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_runner")

tf_runner(
    name = "terraform",
    module = ":vpc",
)
```

Then run any terraform command:
```bash
bazel run //infrastructure:terraform -- init
bazel run //infrastructure:terraform -- plan
bazel run //infrastructure:terraform -- apply
```

## Examples

See the `examples/` directory for usage examples:
- `basic_module` - Simple Terraform module
- `module_with_dependencies` - Module composition
- `nested_modules` - Nested module structure

## Testing

Run all tests:
```bash
bazel test //...
```

## Development

This project uses Nix for development tooling. Run `nix develop` to enter the development shell with all required tools.

## Contributing

Not accepting external contributions at this time while the API stabilizes.

## License

See [LICENSE](LICENSE) file.