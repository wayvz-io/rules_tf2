# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

rules_tf2 is a comprehensive Bazel module that provides advanced Terraform integration for Bazel builds. It enables managing Terraform modules, stacks, and infrastructure deployments with integrated testing, provider management, and Terraform Cloud support.

## Development Workflow

### Feature Development Process
All feature development should follow this Graphite-based workflow:

```bash
# 1. Create a new branch with descriptive message
gt create -am "Brief description of what you're implementing"

# 2. Do the development work
# ... implement features, fix bugs, etc.

# 3. Ensure all tests pass before submitting
bazel test //...

# 4. Update the commit with final changes
gt modify

# 5. Submit the work for review
gt submit
```

This workflow ensures:
- Clean, descriptive commits with proper messaging
- All tests pass before submission
- Consistent branching and review process
- Proper integration with Graphite stack management

## Common Development Commands

### Building and Testing
```bash
# Build all targets
bazel build //...

# Run all tests (most comprehensive way to verify changes)
bazel test //...

# Test specific modules
bazel test //tf2/...
bazel test //tests/...

# Test with verbose output for debugging
bazel test //path/to:target --test_output=all

# Clean build cache (useful for tool download issues)
bazel clean --expunge
```

### Development Environment
```bash
# Enter Nix development environment (provides terraform, tflint, terraform-docs)
nix develop

# Check tools are available
terraform version
tflint --version
terraform-docs --version
```

### Working with Examples
```bash
# Run tests on example modules
bazel test //examples/...

# Test specific example
bazel test //examples/basic_module:all
```

## Code Architecture

### Core Structure
- **tf2/core/**: Core Bazel rule implementations
  - `rules/`: Module, variable, and provider rules (`module.bzl`, `variables.bzl`)
  - `providers/`: Provider management (registry, mirrors, aliases)
- **tf2/execution/**: Terraform execution runtime
  - `macros/`: High-level tf_module macro that generates test targets
  - `tf_runner.bzl`, `tf_cloud_runner.bzl`: Execution engines
- **tf2/testing/**: Comprehensive testing framework
  - Auto-generates format, lint, validate, docs, versions tests for every tf_module
- **tf2/publish/**: OCI artifact publishing
- **tf2/extensions.bzl**: Module extensions for tools and providers

### Key Patterns
- **tf_module macro**: Creates a module + comprehensive test suite automatically
- **Provider registry**: Centralized provider management via MODULE.bazel extensions
- **Tool management**: Automatic download of terraform/tflint/terraform-docs binaries
- **Test generation**: Every tf_module gets format_test, lint_test, validate_test, etc.

### Important Files
- `tf2/def.bzl`: Public API exports - all user-facing rules/macros
- `tf2/extensions.bzl`: Module extensions for tf_providers and tf_tools
- `MODULE.bazel`: Configures tool versions and test providers

## Architecture Principles

### Hermetic Builds
- Tools (terraform, tflint, terraform-docs) are downloaded as Bazel-managed binaries
- Provider binaries are cached and managed by Bazel
- No reliance on host PATH or external package managers

### Comprehensive Testing
Every tf_module automatically generates:
- `*_format_test`: terraform fmt checking
- `*_lint_test`: tflint validation with configurable rulesets
- `*_validate_test`: terraform validate
- `*_versions_check_test`: provider version validation
- `*_doc_test`: terraform-docs README.md validation
- `*_deps_test`: module dependency validation

### Provider Management
- **Registry approach**: Configure providers in MODULE.bazel extension, reference as `@tf_provider_registry//:aws_6`
- **Manual mirrors**: Use `provider_mirror()` for custom providers
- **Version handling**: Multiple provider versions supported simultaneously

### Testing Strategy
- Unit tests in `tests/unit/` verify rule behavior
- Integration tests in `tests/integration/` test real Terraform scenarios
- Examples in `examples/` demonstrate usage patterns and serve as integration tests

## Development Notes

### Working with Rules
- Rule implementations in `tf2/core/rules/` follow standard Bazel patterns
- Always use TfModuleInfo provider for passing module metadata
- Testing rules should be lightweight wrappers around tool execution

### Tool Integration
- Tools are managed by `tf_tools` module extension in `MODULE.bazel`
- TFLint plugins are configured per-provider (aws, azurerm, google, opa)
- Tool paths are resolved at runtime to handle both root module and external dependency scenarios

### Provider Development
- Provider registries are created by module extensions
- Empty registries are created when rules_tf2 is used as external dependency
- Root modules configure actual provider downloads

### Testing Infrastructure
When rules_tf2 is the root module (development), it downloads test providers. When used as a dependency, provider registries are empty and configured by the consuming project.