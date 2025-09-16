# Terraform Lock File Management

This document describes how Terraform lock files are managed centrally in the Bazel build system.

## Overview

The system provides centralized Terraform provider lock file management, eliminating the need for per-machine lock file generation while ensuring reproducible builds across all environments.

## Architecture

### 1. Provider Download and Lock Generation (One-time)

When providers are configured in `MODULE.bazel`:

```python
tf_providers.download(
    providers = {
        "hashicorp/aws": ["6.12.0"],
        "hashicorp/null": ["3.2.4"],
    },
)
```

The `terraform_providers` repository rule:
1. Downloads all specified providers using `terraform init --upgrade`
2. Generates a complete `.terraform.lock.hcl` with hashes for all platforms
3. Parses the lock file and extracts all provider hashes
4. Stores hashes in `provider_locks.bzl` for reuse

### 2. Stack-Specific Lock File Generation

For each `tf_stack`, the system automatically:
1. Generates provider specifications based on declared provider dependencies
2. Creates a `.terraform.lock.hcl` using stored hashes from `provider_locks.bzl`
3. Includes the lock file in validation tests

## Usage

### Basic Stack Definition

```python
load("@tf2//tf:def.bzl", "tf_stack")

tf_stack(
    name = "my_stack",
    providers = [
        "@tf_provider_registry//:aws_6",
        "@tf_provider_registry//:null_3",
    ],
)
```

This automatically creates:
- `:my_stack` - The main stack target
- `:my_stack_provider_config` - Generated provider specifications
- `:my_stack_lock_file` - Generated `.terraform.lock.hcl`
- `:my_stack_validate_test` - Validation test using the lock file

### Building Lock Files

To generate just the lock file:
```bash
bazel build //path/to/stack:stack_name_lock_file
```

To see the generated lock file:
```bash
cat bazel-bin/path/to/stack/.terraform.lock.hcl
```

### Testing with Lock Files

Validation tests automatically use the generated lock file:
```bash
bazel test //path/to/stack:stack_name_validate_test
```

## How It Works

### Provider Hash Storage

The centralized `provider_locks.bzl` file contains all provider hashes:

```python
PROVIDER_LOCKS = {
    "hashicorp/aws:6.12.0": [
        "h1:1u4Vi0sgaEOo1h+u3hcoD/hAe5jLSCXDv3jWCq9jtPU=",
        "h1:8u90EMle+I3Auh4f/LPP6fEfRsAF6xCFnUZF4b7ngEs=",
        # ... more hashes for different platforms
    ],
    # ... more providers
}
```

### Lock File Generation Rule

The `tf_lock_file_generator` rule:
1. Reads the required providers from Bazel module definitions
2. Looks up corresponding hashes from `provider_locks.bzl`
3. Generates a valid `.terraform.lock.hcl` file

```python
tf_lock_file_generator(
    name = "stack_lock",
    provider_locks = "@tf_provider_registry//:provider_locks.bzl",
    versions_file = ":provider_config",
)
```

## Benefits

1. **Single Provider Download**: Providers are downloaded once during repository setup
2. **No Per-Machine Generation**: Lock files are generated from stored hashes
3. **Fast Resolution**: No network calls after initial provider download
4. **Reproducible Builds**: Same hashes used across all environments
5. **Automatic Integration**: Lock files are automatically generated and used in tests

## Updating Provider Versions

When provider versions are updated in `MODULE.bazel`:

1. Run the provider update tool:
   ```bash
   bazel run //:tf-update
   ```

2. The tool will:
   - Update provider versions in `MODULE.bazel`
   - Trigger provider re-download
   - Regenerate `provider_locks.bzl` with new hashes
   - Update all provider specifications

3. Test the changes:
   ```bash
   bazel test //iac/...
   ```

## Troubleshooting

### Missing Provider in Lock File

If a provider is missing from the lock file:
1. Ensure it's declared in `MODULE.bazel`
2. Check that the version matches exactly
3. Verify `provider_locks.bzl` contains the provider

### Lock File Not Generated

If the lock file isn't being generated:
1. Check you're not in a test package (lock files aren't generated for tests)
2. Ensure providers are specified in the `tf_stack` rule
3. Verify the `tf_provider_registry` repository is available

### Validation Failures

If validation fails with lock file issues:
1. Check the generated lock file exists: `bazel build //path:stack_lock_file`
2. Verify provider versions match between specifications and lock file
3. Ensure the provider registry contains the required providers

## Implementation Details

### Files Involved

- `build/rules/tf2/tf/core/repositories/terraform_providers.bzl` - Downloads providers and generates `provider_locks.bzl`
- `build/rules/tf2/tf/core/providers/lock_file_generator.bzl` - Rule for generating stack-specific lock files
- `build/rules/tf2/tf/execution/macros/macros.bzl` - Integration in `tf_stack` macro
- `build/rules/tf2/tf/testing/validate.bzl` - Validation test using lock files

### Module Extension Integration

The system is integrated with Bazel's module extension system:
- Provider declarations in `MODULE.bazel` trigger downloads
- The `tf_providers` extension manages provider repositories
- Lock data is stored and reused across the build

## Future Enhancements

Potential improvements to the system:
1. Support for provider version constraints (not just exact versions)
2. Automatic detection of missing providers
3. Integration with remote caching for faster CI builds
4. Support for private provider registries