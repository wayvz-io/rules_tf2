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
- **Execution**: Compares versions.tf.json with generated version from provider_configurations
- **Output**: "versions.tf.json is up to date"

- **Generator Target**: `simple_module_generate_versions`
- **Rule**: `tf_generate_versions`
- **Purpose**: Updates versions.tf.json from provider_configurations

### 6. Validation Test
- **Target**: `simple_module_validate_test`
- **Rule**: `tf_validate_test`
- **Execution**:
  1. Copies module files to temp directory
  2. Runs `terraform init -backend=false -upgrade=false`
     - With `-plugin-dir` if provider_library is specified
  3. Runs `terraform validate -no-color`
- **Output**: 
  - "Terraform has been successfully initialized!"
  - "Success! The configuration is valid."

## Provider Management

### Provider Library
- **Rule**: `provider_library`
- **Purpose**: Downloads and caches exact provider versions
- **Execution**:
  1. Creates versions.tf.json with exact versions
  2. Runs `terraform init` to download providers
  3. Runs `terraform providers mirror` to create local cache

### Provider Configurations
- **Rule**: `provider_configurations`
- **Purpose**: Generates versions.tf.json with version constraints
- **Output**: versions.tf.json file for modules

## Test Execution Summary

For each **module**, these tests run:
1. Format check (terraform fmt)
2. Lint check (tflint)
3. Documentation check (terraform-docs)
4. Version check (file comparison)
5. Validation (terraform init + validate)

All tests are properly executing their respective tools and validating the Terraform code.