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
gt modify -am "Updated commit message describing the changes"
# Note: gt modify is equivalent to git add -A + git commit --amend
# The -a flag stages all changes, -m provides the message

# 5. Create a new branch for next phase of work (if needed)
gt create -am "Next phase description"

# 6. Submit the work for review when complete
gt submit
```

**Important Graphite Commands:**
- `gt modify -am "message"`: Stage all changes and amend current commit (like git add -A + git commit --amend)
- `gt create -am "message"`: Create new branch with commit message
- `gt submit`: Submit changes for review
- `gt restack`: Rebase stack on latest main

This workflow ensures:
- Clean, descriptive commits with proper messaging
- All tests pass before submission
- Consistent branching and review process
- Proper integration with Graphite stack management
- Easy tracking of multi-phase development

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

### Core Structure (Updated)
- **tf2/core/**: Core Bazel rule implementations
  - `module.bzl`: Core tf_module_rule implementation
  - `runner.bzl`: General-purpose tf_runner for executing terraform commands
  - `providers.bzl`: Information providers (TfModuleInfo, TfProviderInfo, etc.)
- **tf2/macros/**: Public API macros
  - `tf_module.bzl`: High-level tf_module macro that generates test targets
- **tf2/testing/**: Comprehensive testing framework (reorganized)
  - `format/`: Terraform format testing and fixing
  - `lint/`: Linting tests and rules
  - `validate/`: Validation tests
  - `docs/`: Documentation tests and generation
  - `versions/`: Version checking and generation
  - `deps/`: Dependency testing
- **tf2/runtime/**: Runtime execution utilities
  - `staging.bzl`: File staging utilities for terraform execution
- **tf2/internal/**: Internal utilities
  - `file_ops.bzl`: File operation utilities using Starlark actions
- **tf2/module/**: Legacy module implementations (gradual migration target)
- **tf2/providers/**: Provider management (registry, mirrors, aliases)
- **tf2/publish/**: OCI artifact publishing and cloud runners
- **tf2/tools/**: Tool management and runners
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
- File operations use Starlark actions instead of shell scripts where possible

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
- Unit tests in `tests/unit/` verify rule behavior, including new core components
- Integration tests in `tests/integration/` test real Terraform scenarios
- Examples in `examples/` demonstrate usage patterns and serve as integration tests
- New staging utilities have dedicated unit tests in `tests/unit/core/`

### Code Organization Improvements
- **Clear separation of concerns**: Core rules, macros, testing, and utilities are separated
- **Reduced shell script usage**: File operations moved to Starlark actions
- **Improved testability**: Core utilities can be unit tested independently
- **Better code reuse**: Shared utilities in `tf2/internal/` and `tf2/runtime/`

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