# rules_tf2

Bazel rules for managing Terraform infrastructure. `rules_tf2` manages Terraform modules through Bazel, with integrated testing, provider/tool management, external module support, policy testing, and Terraform Cloud/Enterprise integration.

> [!WARNING]
> **This project is unmaintained.** It was extracted from an internal repository and is published as-is for reference and reuse. It works (the test suite passes), but it is **alpha-quality, the APIs may change, and it is not actively developed or supported.** Fork it if you want to build on it. See [Contributing](#contributing).

## Status

- **Alpha** - core functionality works; APIs may change.
- **Policy testing** - OPA and Sentinel format/test rules are implemented and tested (`tf_opa_test`, `tf_sentinel_test`).
- **Publishing** - OCI and Terraform-registry publishing (`tf_publish_oci`, `tf_publish_registry`) are implemented but rougher than the rest.

## Features

- Terraform module management through Bazel
- Terraform Cloud/Enterprise integration
- Provider management with automatic downloading and caching
- Run arbitrary terraform commands through Bazel
- Comprehensive testing (format, lint, validate, docs)
- Tool integration (terraform, tflint, terraform-docs)

## Project Structure

```
tf2/
├── agent/             # TFC agent image building
├── gazelle/           # Terraform Gazelle extension (dev tool)
├── internal/          # Internal utilities
├── macros/            # Public API macros (tf_module)
├── modules/           # External module registry management
├── opa/               # OPA policy testing
├── providers/         # Provider management
├── publish/           # OCI / registry publishing
├── sentinel/          # Sentinel policy testing
├── tfcloud/           # Terraform Cloud integration
├── tfcore/            # Core Terraform functionality
├── tfdocs/            # terraform-docs integration
├── tflint/            # tflint integration
├── tools/             # Tool management
└── def.bzl            # Public API exports
```

## Quick Start

### 1. Add to MODULE.bazel

`rules_tf2` is **not** published to the Bazel Central Registry, so an override is
required. Use a `git_override` pinned to a tag (or commit):

```starlark
bazel_dep(name = "rules_tf2", version = "0.1.0")

git_override(
    module_name = "rules_tf2",
    remote = "https://github.com/wayvz-io/rules_tf2.git",
    tag = "v0.1.0",
)

# Providers and tools are configured from a versions.json file.
# Configure providers
tf_providers = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_providers")
tf_providers.download(
    versions_file = "//path/to:versions.json",
)
use_repo(tf_providers, "tf_provider_registry")

# Configure tools (terraform, tflint, terraform-docs)
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")
tf_tools.from_versions_json(
    versions_file = "//path/to:versions.json",
)
use_repo(tf_tools, "tf_tool_registry", "tflint_plugin_registry")
```

### 2. Define a Terraform Module

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "vpc",
    # Always list .tf files explicitly - do not use glob().
    srcs = [
        "main.tf",
        "outputs.tf",
        "terraform.tf",
        "variables.tf",
        "README.md",
    ],
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
- `parent_module` / `child_with_nested_dep` / `nested_dependency_test` - Module dependency graphs
- `parent_with_explicit_deps` - Explicit dependency declaration
- `opa_policy` / `sentinel_policy` - Policy testing

## Testing

Run all tests:
```bash
bazel test //...
```

## Development

This project uses Nix for development tooling. Run `nix develop` to enter the development shell with all required tools.

## Contributing

This repository is **unmaintained** and provided as-is. Issues and pull requests
are not actively monitored and may not receive a response. You are welcome to
**fork** it and build on it under the terms of the licence.

## License

Licensed under the [MIT License](LICENSE).