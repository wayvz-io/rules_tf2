# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

rules_tf2 is a Bazel module providing Terraform integration for Bazel builds. It manages Terraform modules with integrated testing, provider management, and Terraform Cloud support.

**Status**: Alpha - Core functionality works but APIs may change.

## Development Commands

### Build and Test
```bash
bazel build //...              # Build all targets
bazel test //...               # Run all tests (verify before submitting)
bazel test //path/to:target --test_output=all   # Debug specific test
bazel clean --expunge          # Clean cache (for tool download issues)
```

### Graphite Workflow
```bash
gt create -am "Brief description"    # Create branch with commit
gt modify -am "Updated message"      # Stage all + amend commit
gt restack                           # Rebase on main
gt submit                            # Submit for review
```

### Development Environment
```bash
nix develop                    # Enter dev shell (terraform, tflint, terraform-docs)
```

## Code Architecture

### Public API (`tf2/def.bzl`)
All user-facing rules/macros:
- `tf_module` - Main macro for Terraform modules with auto-generated tests
- `tf_runner` - Run arbitrary terraform commands
- `tf_test` - Explicit test targets
- `tf_cloud_workspace` - Terraform Cloud integration
- `provider_mirror` - Custom provider management

### Core Directories
- **tf2/macros/tf_module.bzl**: The `tf_module` macro - generates module + 10+ test targets automatically
- **tf2/tfcore/**: Core terraform operations (validate, runner, module, versions)
- **tf2/tflint/**: TFLint integration (test, format, validate, config)
- **tf2/tfdocs/**: terraform-docs integration (test, generator)
- **tf2/providers/**: Provider management (registry, download, mirrors)
- **tf2/tools/**: Tool download and management (terraform, tflint, terraform-docs)
- **tf2/extensions.bzl**: Module extensions (`tf_providers`, `tf_tools`)
- **tf2/internal/**: Internal utilities (staging, file_ops, organization)

### Configuration Files
- **tests/providers/versions.json**: Tool and provider versions for development
- **MODULE.bazel.lock**: Provider hashes are automatically generated and stored in the Bazel lockfile via module extension facts (requires Bazel 8.5+)

## Key Concepts

### tf_module Macro
Creates a Terraform module with comprehensive test suite:
```starlark
tf_module(
    name = "my_module",
    srcs = glob(["*.tf"]) + ["README.md"],  # Required
    providers = ["@tf_provider_registry//:aws_6"],
)
```

Auto-generates: `*_format_test`, `*_lint_test`, `*_validate_test`, `*_versions_check_test`, `*_doc_test`, `*_deps_test`, `*_organization_check_test`, `*_untracked_files_test`, `*_no_lockfile_test`, `*_tflint_validate_test`

### Provider Aliasing
Providers are aliased to major version: `aws_6`, `random_3`, `azurerm_4`
- For 0.x versions: `time_0`, `tfe_0` (because 0.x can have breaking changes between minor versions)
- Reference as: `@tf_provider_registry//:aws_6`

### Provider Inheritance
Child modules' providers are inherited by parents. A parent only declares providers it directly uses, but the lockfile contains all providers from the dependency tree.

### Module Extensions (MODULE.bazel)
```starlark
# Providers - hashes are auto-generated and cached in MODULE.bazel.lock
tf_providers = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_providers")
tf_providers.download(
    versions_file = "path/to/versions.json",
)
use_repo(tf_providers, "tf_provider_registry")

# Tools
tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")
tf_tools.from_versions_json(versions_file = "path/to/versions.json")
use_repo(tf_tools, "tf_tool_registry", "tflint_plugin_registry")
```

### Provider Hash Generation
Provider hashes (h1 and zh) are automatically generated when:
1. A new provider/version is added to versions.json
2. The MODULE.bazel.lock doesn't have cached hashes for that provider

The extension uses `terraform providers lock` internally to generate hashes for all platforms. This happens during `bazel build` and results are cached in MODULE.bazel.lock via the `facts` mechanism (requires Bazel 8.5+).

## Development Notes

### Adding New Rules
- Use TfModuleInfo provider for passing module metadata
- Testing rules should be lightweight wrappers around tool execution
- Prefer Starlark actions over shell scripts for file operations

### Root vs Dependency Mode
When rules_tf2 is the root module (development), it downloads test providers. When used as a dependency, provider registries are empty and configured by the consuming project.

### Tool/Provider Path Resolution
Tool paths are resolved at runtime to handle both root module and external dependency scenarios. The module extension creates individual download repositories for each platform.

### TFLint Plugins
Configured per-provider in versions.json: aws, azurerm, google, opa, plus a built-in `tf2` plugin at `//go/tflint_ruleset:tflint-ruleset-tf2`.