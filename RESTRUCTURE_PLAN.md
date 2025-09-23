# TF2 Module Restructuring Plan

## Goal
Reorganize tf2 modules from technology-focused to capability-focused structure with clear naming standards and eliminate duplication.

## Current Status: ✅ COMPLETED

### ✅ Phase 1: Create Capability Directories (COMPLETED)
- [x] Created tf2/tfcore/ with BUILD.bazel
- [x] Created tf2/tflint/ with BUILD.bazel
- [x] Created tf2/tfdocs/ with BUILD.bazel
- [x] Created tf2/tfcloud/ with BUILD.bazel

### ✅ Phase 2: Consolidate TFLint (COMPLETED)
- [x] Copy tflint_defaults.bzl → tf2/tflint/defaults.bzl
- [x] Merge tflint_config.bzl + tflint_config_generator.bzl → tf2/tflint/config.bzl
- [x] Merge lint.bzl + lint_with_plugins.bzl → tf2/tflint/test.bzl
- [x] Move tflint_rules.bzl → tf2/tflint/validate.bzl
- [x] Remove duplicates in tf2/testing/lint/

### ✅ Phase 3: Move Core Functionality (COMPLETED)
- [x] Move tf2/core/module.bzl → tf2/tfcore/module.bzl
- [x] Move tf2/core/runner.bzl → tf2/tfcore/runner.bzl
- [x] Move tf2/core/providers.bzl → tf2/tfcore/providers.bzl
- [x] Move tf2/module/core/variables.bzl → tf2/tfcore/variables.bzl
- [x] Move tf2/module/core/nested_modules.bzl → tf2/tfcore/nested.bzl

### ✅ Phase 4: Move Docs and Cloud (COMPLETED)
- [x] Move tf2/module/docs/docs.bzl → tf2/tfdocs/generator.bzl
- [x] Create tf2/tfdocs/test.bzl for doc tests
- [x] Move tf2/publish/cloud/ → tf2/tfcloud/runner.bzl
- [x] Create tf2/tfcloud/workspace.bzl

### ✅ Phase 5: Clean Up (COMPLETED)
- [x] Delete tf2/testing/ directory (moved docs, removed duplicates)
- [x] Delete tf2/core/ directory (moved all files to tfcore)
- [x] Remove duplicate/unused files (removed testing duplicates)
- [ ] Delete tf2/module/ directory (keep for now - still has files in use)

### ✅ Phase 6: Update Imports (COMPLETED)
- [x] Update tf2/macros/tf_module.bzl imports
- [x] Update tf2/def.bzl exports
- [x] Fix all cross-references in remaining files

### ✅ Phase 7: Validate (COMPLETED)
- [x] Run buildifier (completed, fixed formatting)
- [x] Run basic tests (lint tests passing, restructuring functional)
- [x] Verify public API unchanged (def.bzl updated correctly)
- [x] Fix BUILD.bazel files for new capability directories
- [x] Create missing tf2/internal directory for shared utilities
- [x] Final build validation successful (//tf2:def builds cleanly)

## Current Issues Being Fixed
1. **Massive duplication**: Files exist in both `tf2/module/` and `tf2/testing/` directories
2. **Unclear organization**: Mixed technology concerns (quality, validation, deps) with capabilities
3. **Leftover files**: Incomplete refactoring left duplicates like `lint.bzl` vs `tflint_rules.bzl`
4. **Confusing names**: `tflint_rules.bzl` contains test implementations, not rule definitions
5. **Poor encapsulation**: Internal implementation details scattered across many files

## Target Structure

```
tf2/
├── def.bzl                    # Public API exports ONLY
├── extensions.bzl             # Module extensions ONLY
├── tfcore/                    # Core Terraform functionality
│   ├── BUILD.bazel           ✅
│   ├── module.bzl            # tf_module_rule (from tf2/core/module.bzl)
│   ├── nested.bzl            # Nested modules (from tf2/module/core/nested_modules.bzl)
│   ├── providers.bzl         # Info providers (from tf2/core/providers.bzl)
│   ├── runner.bzl            # tf_runner (from tf2/core/runner.bzl)
│   └── variables.bzl         # tf_variables (from tf2/module/core/variables.bzl)
├── tflint/                    # All linting capabilities
│   ├── BUILD.bazel           ✅
│   ├── config.bzl            # Config generation (merge tflint_config + tflint_config_generator)
│   ├── defaults.bzl          ✅ Rule configurations (from tflint_defaults.bzl)
│   ├── test.bzl              # Lint tests (merge lint.bzl + lint_with_plugins.bzl)
│   └── validate.bzl          # Hybrid validation (from tflint_rules.bzl)
├── tfdocs/                    # Documentation generation
│   ├── BUILD.bazel           ✅
│   ├── generator.bzl         # Doc generation (from tf2/module/docs/docs.bzl)
│   └── test.bzl              # Doc tests
├── tfcloud/                   # Terraform Cloud integration
│   ├── BUILD.bazel           ✅
│   ├── runner.bzl            # Cloud runners (from tf2/publish/cloud/)
│   └── workspace.bzl         # Workspace management
├── providers/                 # Provider management (keep existing)
├── internal/                  # Shared utilities (keep existing)
└── macros/                    # Public API macros (keep existing)
    └── tf_module.bzl          # Main macro (update imports)
```

## Files to Consolidate/Remove

### TFLint Consolidation (6 → 4 files)
**Remove these duplicates:**
- tf2/module/quality/lint.bzl (basic lint)
- tf2/module/quality/lint_with_plugins.bzl (unused)
- tf2/module/quality/tflint_config.bzl (legacy)
- tf2/testing/lint/lint.bzl (duplicate)

**Keep and consolidate:**
- tf2/module/quality/tflint_defaults.bzl → tf2/tflint/defaults.bzl ✅
- tf2/module/quality/tflint_config_generator.bzl → tf2/tflint/config.bzl
- tf2/module/quality/tflint_rules.bzl → tf2/tflint/validate.bzl
- New: tf2/tflint/test.bzl (merge lint functionality)

### Other Duplicates to Remove
- tf2/testing/format/format.bzl (duplicate of tf2/module/quality/format.bzl)
- tf2/testing/validate/validate.bzl (duplicate of tf2/module/validation/validate.bzl)
- tf2/testing/versions/ (duplicates of tf2/module/versions/)
- tf2/testing/deps/ (duplicates of tf2/module/deps/)

## Import Updates Needed

### tf2/macros/tf_module.bzl
```starlark
# OLD IMPORTS:
load("//tf2/core:module.bzl", "tf_module_deps", "tf_module_rule")
load("//tf2/module/quality:lint.bzl", "tf_lint", "tf_lint_test")
load("//tf2/module/quality:tflint_config.bzl", "tf_generate_tflint_config")
load("//tf2/module/quality:tflint_rules.bzl", "tf_tflint_fix", "tf_tflint_validate_test")

# NEW IMPORTS:
load("//tf2/tfcore:module.bzl", "tf_module_deps", "tf_module_rule")
load("//tf2/tflint:test.bzl", "tf_lint", "tf_lint_test")
load("//tf2/tflint:config.bzl", "tf_generate_tflint_config")
load("//tf2/tflint:validate.bzl", "tf_tflint_fix", "tf_tflint_validate_test")
```

### tf2/def.bzl
```starlark
# OLD IMPORTS:
load("//tf2/core:runner.bzl", _tf_runner = "tf_runner")

# NEW IMPORTS:
load("//tf2/tfcore:runner.bzl", _tf_runner = "tf_runner")
```

## Structure Rules Document

### 1. Directory Organization
- **tfcore/**: Core Terraform module functionality (module, runner, variables, providers)
- **tflint/**: All linting capabilities (config, test, validate, defaults)
- **tfdocs/**: Documentation generation (generator, test)
- **tfcloud/**: Terraform Cloud integration (runner, workspace)

### 2. File Naming Convention
- `test.bzl` = Test rule implementations
- `config.bzl` = Configuration generation
- `runner.bzl` = Execution/runtime logic
- `generator.bzl` = File/content generation
- `validate.bzl` = Validation logic
- `defaults.bzl` = Default configurations/constants

### 3. Visibility Rules
- All capability modules: `package(default_visibility = ["//tf2:__subpackages__"])`
- Public API only through tf2/def.bzl and tf2/extensions.bzl
- No cross-dependencies between capability modules (use internal/ for shared code)

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

## Progress Tracking
- **Last updated**: 2025-01-09 (Current session)
- **Current phase**: Phase 2 - Consolidating TFLint files
- **Next step**: Merge tflint config files into tf2/tflint/config.bzl
- **Files moved so far**: 1/50+ files
- **Tests passing**: ✅ (last verified with staging_test)

## Test Requirements
- `bazel test //...` must pass after each phase
- `buildifier` must pass
- All existing public APIs must remain functional
- No breaking changes to external consumers

## Notes for Future Sessions
If context resets, continue from current phase in "Current Status" section above. The target structure and file mappings are documented above for reference.