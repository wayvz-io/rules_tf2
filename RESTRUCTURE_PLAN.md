# TF2 Module Restructuring Plan

## Current Issues
1. **Vague naming**: "core" contains mixed concerns (providers, repos, rules, cdktf)
2. **Scattered features**: Provider logic split between core/providers and core/repositories
3. **Mixed repository rules**: core/repositories contains both provider AND tool repos
4. **Testing confusion**: "testing" directory contains lifecycle management (format, lint, validate)
5. **Unclear separation**: No clear boundary between public API and internal implementation
6. **Technical grouping**: Organized by type (rules, repositories) rather than feature

## Proposed Structure

```
tf2/
├── providers/                  # Everything related to provider management
│   ├── registry/               # Provider registry and metadata management
│   │   ├── provider_metadata.bzl      # Provider version metadata (renamed from provider_alias_simple)
│   │   ├── provider_mirror.bzl        # Provider mirror management
│   │   └── filesystem_mirror.bzl      # Filesystem mirror aggregation
│   ├── download/               # Provider download mechanisms
│   │   ├── provider_download_action.bzl
│   │   └── provider_http_files.bzl
│   ├── repository/             # Repository rules for providers
│   │   └── terraform_providers.bzl
│   └── BUILD.bazel
│
├── tools/                      # Tool management (terraform, tflint, terraform-docs)
│   ├── download/               # Tool download and management
│   │   └── tools_repository.bzl       # Repository rule for tools
│   ├── runners/                # Tool execution wrappers
│   │   ├── terraform.bzl              # Terraform execution utilities
│   │   ├── tflint.bzl                 # TFLint execution utilities
│   │   └── tfdoc.bzl                  # Terraform-docs utilities
│   └── BUILD.bazel
│
├── module/                     # Module lifecycle management
│   ├── core/                   # Core module rules
│   │   ├── tf_module.bzl              # Core tf_module rule implementation
│   │   ├── nested_modules.bzl         # Nested module processing
│   │   └── variables.bzl              # Variable management
│   ├── validation/             # Validation and testing
│   │   ├── validate.bzl               # terraform validate
│   │   ├── test.bzl                   # terraform test
│   │   └── module_deps.bzl            # Module dependency testing
│   ├── quality/                # Code quality checks
│   │   ├── format.bzl                 # terraform fmt
│   │   ├── lint.bzl                   # tflint integration
│   │   ├── tflint_config.bzl          # TFLint configuration generation
│   │   └── organization.bzl           # File organization checks
│   ├── docs/                   # Documentation generation
│   │   └── generate.bzl               # terraform-docs integration
│   ├── versions/               # Version management
│   │   ├── versions.bzl               # Version configuration
│   │   ├── lockfile.bzl               # Lock file management
│   │   └── versions_hcl.bzl           # HCL version generation
│   ├── macro/                  # High-level macro
│   │   └── tf_module.bzl              # Public tf_module macro that orchestrates everything
│   └── BUILD.bazel
│
├── publish/                    # Publishing capabilities
│   ├── oci/                    # OCI/container registry publishing
│   │   ├── oci_push.bzl
│   │   └── config.bzl
│   ├── cloud/                  # Terraform Cloud integration
│   │   ├── tf_cloud_runner.bzl
│   │   └── tf_cloud_workspace.bzl
│   └── BUILD.bazel
│
├── runner/                     # Terraform execution runners
│   ├── tf_runner.bzl           # Local terraform runner
│   └── BUILD.bazel
│
├── cdktf/                      # CDKTF support (separate feature)
│   ├── repository/
│   │   └── cdktf_repository.bzl
│   └── BUILD.bazel
│
├── internal/                   # Internal shared utilities
│   ├── providers/              # Provider info definitions
│   │   └── info.bzl                   # TfProviderAliasInfo, etc.
│   ├── utils/                  # Shared utilities
│   │   ├── runfiles.bzl
│   │   ├── files.bzl
│   │   ├── tool_paths.bzl
│   │   └── actions.bzl
│   ├── scripts/                # Helper scripts
│   │   └── regenerate_all.bzl
│   └── BUILD.bazel
│
├── extensions.bzl              # Module extensions (public API)
│   # - tf_providers
│   # - tf_tools
│   # - tfc_config
│   # - cdktf_providers
│
└── def.bzl                     # Public API exports
    # - tf_module (from module/macro/)
    # - provider_mirror (from providers/registry/)
    # - tf_module_push_oci (from publish/oci/)
    # - tf_cloud_workspace (from publish/cloud/)
    # - tf_runner (from runner/)
    # - tf_variables (from module/core/)
```

## Migration Strategy

### Phase 1: Create new structure with symlinks
1. Create new directory structure
2. Move files to new locations
3. Create compatibility symlinks from old locations
4. Update imports gradually
5. Ensure all tests pass

### Phase 2: Update imports
1. Update internal imports to use new paths
2. Update def.bzl to import from new locations
3. Update extensions.bzl imports
4. Update BUILD.bazel files

### Phase 3: Remove compatibility layer
1. Remove symlinks
2. Final test pass
3. Update documentation

## Benefits of New Structure

1. **Feature-oriented**: Each directory represents a clear feature area
2. **Clear boundaries**: `internal/` for shared utilities, clear public API in def.bzl
3. **Logical grouping**: Related functionality stays together
4. **Better discoverability**: Easy to find where specific functionality lives
5. **Separation of concerns**: Providers, tools, modules, and publishing are clearly separated
6. **Consistent patterns**: Each major area has similar substructure

## Test Requirements
- `bazel test //...` must pass
- `bazel build //:mod` must work
- All existing public APIs must remain functional
- No breaking changes to external consumers