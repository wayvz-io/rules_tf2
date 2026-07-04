# Terraform Rules Execution Trace

## Module Test Suite (`tf_module`)

When you define a `tf_module`, the macro creates these targets:

### 1. Main Module Target
- **Target**: `simple_module`
- **Rule**: `tf_module_rule`
- **Purpose**: Packages source files and provides module metadata

### 2. Format Test & Formatter
- **Test Target**: `simple_module_format_test`
- **Rule**: `tf_format_test`
- **Execution**: Runs `terraform fmt -check` on each `.tf` file
- **Output**: "All files are properly formatted"

- **Format Target**: `simple_module_format`
- **Rule**: `tf_format`
- **Purpose**: Runs `terraform fmt` to fix formatting

### 3. Documentation Test & Generator
- **Test Target**: `simple_module_doc_test`
- **Rule**: `tf_doc_test`
- **Execution**: 
  1. Copies module files to temp directory
  2. Runs `terraform-docs markdown .` with config
  3. Compares generated docs with existing README.md
- **Output**: "✓ README.md is up-to-date"

- **Generator Target**: `simple_module_generate_docs`
- **Rule**: `tf_generate_docs`
- **Purpose**: Updates README.md with terraform-docs

### 4. Lint Test
- **Target**: `simple_module_lint_test`
- **Rule**: `tf_lint_test`
- **Execution**:
  1. Copies module files and config to temp directory
  2. Runs `tflint --init` to install plugins
  3. Runs `tflint` with config
- **Output**: "All plugins are already installed" (and lint results)

### 5. Versions Check & Generator
- **Test Target**: `simple_module_versions_check_test`
- **Rule**: `tf_versions_check_test`
- **Execution**: Compares the module's committed version constraints (`versions.tf`) against the constraints generated from the declared providers
- **Output**: "versions are up to date"

- **Generator Target**: `simple_module_generate_versions`
- **Rule**: `tf_generate_versions`
- **Purpose**: Writes the required-provider version constraints into `versions.tf` (or updates existing `.tf` files)

### 6. Validation Test
- **Target**: `simple_module_validate_test`
- **Rule**: `tf_validate_test`
- **Execution**:
  1. Copies module files to temp directory
  2. Runs `terraform init -backend=false -upgrade=false -lockfile=readonly`
     - Provider resolution is pointed at the filesystem mirror through a generated `.terraformrc` (`filesystem_mirror`, exported via `TF_CLI_CONFIG_FILE`) so no network access is needed
  3. Runs `terraform validate -no-color`
- **Output**: 
  - "Terraform has been successfully initialized!"
  - "Success! The configuration is valid."

## Provider Management

Providers are declared centrally in `versions.json` and consumed through the `tf_providers` module extension rather than per-module rules. See `PROVIDER_ARCHITECTURE.md` for the full design.

### Provider Registry & Hashes
- **Extension**: `tf_providers` (creates `@tf_provider_registry`)
- **Purpose**: Resolve provider requirements and generate reproducible hashes
- **Execution**:
  1. Reads provider requirements from `versions.json`
  2. Checks `module_ctx.facts` for cached hashes; for missing providers runs `terraform providers lock` inline
  3. Caches the generated h1/zh hashes in `MODULE.bazel.lock` (requires Bazel 8.5+)
  4. Providers are referenced by major-version alias, e.g. `@tf_provider_registry//:aws_6`

### Filesystem Mirror
- **Purpose**: Aggregate downloaded providers into a local mirror so Terraform runs offline
- **Execution**:
  1. Each provider/platform is downloaded into its own repository on demand
  2. Providers are assembled into a filesystem mirror
  3. Terraform init uses the mirror via a generated `.terraformrc` `filesystem_mirror` block (`TF_CLI_CONFIG_FILE`), so there is no network access during builds

## Test Execution Summary

For each **module**, these tests run:
1. Format check (terraform fmt)
2. Lint check (tflint)
3. Documentation check (terraform-docs)
4. Version check (file comparison)
5. Validation (terraform init + validate)

All tests are properly executing their respective tools and validating the Terraform code.