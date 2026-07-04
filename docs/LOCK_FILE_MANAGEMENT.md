# Terraform Lock File Management

This document describes how Terraform lock files are managed centrally in the Bazel build system.

## Overview

The system provides centralized Terraform provider lock file management, eliminating the need for per-machine lock file generation while ensuring reproducible builds across all environments.

**Key feature**: Provider hashes are automatically generated and cached in `MODULE.bazel.lock` via Bazel's module extension facts mechanism. No manual lock file management is required.

## Architecture

### Provider Hash Generation (Automatic)

When providers are configured in `versions.json`:

```json
{
  "providers": {
    "hashicorp/aws": ["6.26.0"],
    "hashicorp/null": ["3.2.4"]
  }
}
```

The `tf_providers` module extension automatically:
1. Checks `MODULE.bazel.lock` for cached hashes (via `module_ctx.facts`)
2. For any missing providers, downloads terraform and runs `terraform providers lock`
3. Parses the generated `.terraform.lock.hcl` to extract h1/zh hashes
4. Stores new hashes in `MODULE.bazel.lock` via `extension_metadata(facts=...)`
5. Creates provider download repositories for all platforms

```
versions.json (input)
     │
     ▼
┌──────────────────────────────────────────────────┐
│  tf_providers Extension (loading phase)          │
│  1. Read versions.json                           │
│  2. Check module_ctx.facts for cached hashes     │
│  3. For missing providers:                       │
│     - Download terraform inline                  │
│     - Run terraform providers lock               │
│     - Parse hashes from .terraform.lock.hcl      │
│  4. Return extension_metadata(facts=hashes)      │
└──────────────────────────────────────────────────┘
     │
     ▼
MODULE.bazel.lock (facts section stores all hashes)
     │
     ▼
Provider repositories (ready to use)
```

### Per-Module Lock File Generation

For each `tf_module`, the system automatically:
1. Generates provider specifications based on declared provider dependencies
2. Creates a `.terraform.lock.hcl` using stored hashes from `@tf_provider_registry//:provider_locks.json`
3. Includes the lock file in validation tests

## Usage

### Basic Module Definition

```python
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "my_module",
    srcs = [
        "main.tf",
        "terraform.tf",
    ],
    providers = [
        "@tf_provider_registry//:aws_6",
        "@tf_provider_registry//:null_3",
    ],
)
```

This automatically creates (among the generated test targets):
- `:my_module` - The main module target
- `:my_module_lock_file` - Generated `.terraform.lock.hcl`
- `:my_module_validate_test` - Validation test using the lock file

### Building Lock Files

To generate just the lock file:
```bash
bazel build //path/to/module:module_name_lock_file
```

To see the generated lock file:
```bash
cat bazel-bin/path/to/module/.terraform.lock.hcl
```

### Testing with Lock Files

Validation tests automatically use the generated lock file:
```bash
bazel test //path/to/module:module_name_validate_test
```

## How It Works

### Provider Hash Storage

Provider hashes are stored in `MODULE.bazel.lock` under the facts section:

```json
{
  "facts": {
    "//tf2:extensions.bzl%tf_providers": {
      "hashicorp/aws:6.26.0": {
        "h1": ["hash1...", "hash2..."],
        "zh": ["zhhash1...", "zhhash2..."]
      }
    }
  }
}
```

The extension also generates `@tf_provider_registry//:provider_locks.json` for use by lock file generation rules.

### Lock File Generation Rule

The `tf_lock_file_generator` rule:
1. Reads the required providers from Bazel module definitions
2. Looks up corresponding hashes from `@tf_provider_registry//:provider_locks.json`
3. Generates a valid `.terraform.lock.hcl` file

```python
tf_lock_file_generator(
    name = "module_lock",
    provider_locks = "@tf_provider_registry//:provider_locks.json",
    versions_file = ":provider_config",
)
```

## Benefits

1. **Automatic Hash Generation**: No manual scripts needed - hashes generated on first build
2. **Persistent Caching**: Hashes cached in `MODULE.bazel.lock`, survive clean builds
3. **Single Provider Download**: Providers downloaded once during hash generation
4. **No Per-Machine Generation**: Lock files are generated from stored hashes
5. **Fast Resolution**: No network calls after initial hash generation
6. **Reproducible Builds**: Same hashes used across all environments
7. **Automatic Integration**: Lock files are automatically generated and used in tests

## Updating Provider Versions

When provider versions are updated in `versions.json`:

1. Edit `versions.json` to add/update provider versions:
   ```bash
   vim tests/providers/versions.json
   ```

2. Run any bazel command - hashes will be auto-generated:
   ```bash
   bazel build //...
   # INFO: Generating hashes for hashicorp/newprovider:1.0.0 (this may take a while)
   ```

3. The new hashes are automatically stored in `MODULE.bazel.lock`

4. Test the changes:
   ```bash
   bazel test //...
   ```

5. Commit `versions.json` and `MODULE.bazel.lock`:
   ```bash
   git add versions.json MODULE.bazel.lock
   git commit -m "Update provider versions"
   ```

## Requirements

- **Bazel 8.5+**: Required for `module_ctx.facts` support
- **Network access**: Required only when generating hashes for new providers

## Troubleshooting

### Missing Provider in Lock File

If a provider is missing from the lock file:
1. Ensure it's declared in `versions.json`
2. Check that `MODULE.bazel.lock` contains hashes for the provider
3. Run `bazel build //...` to trigger hash generation if missing

### Hash Generation Taking Too Long

Hash generation runs `terraform providers lock` which downloads provider binaries for 5 platforms. For large providers (e.g., AWS), this can take several minutes. This is a one-time cost - subsequent builds use cached hashes.

### Validation Failures

If validation fails with lock file issues:
1. Check the generated lock file exists: `bazel build //path:module_lock_file`
2. Verify provider versions match between specifications and lock file
3. Ensure the provider registry contains the required providers

## Implementation Details

### Files Involved

- `tf2/extensions.bzl` - Module extension that generates hashes and creates provider repositories
- `tf2/providers/repository/hcl_parser.bzl` - Parses `.terraform.lock.hcl` files
- `tf2/providers/repository/terraform_providers.bzl` - Repository rule for provider registry
- `tf2/tfcore/versions/lockfile.bzl` - Rule for generating per-module lock files

### Module Extension Flow

The `tf_providers` extension:
1. Reads `versions.json` via `module_ctx.read()`
2. Checks `module_ctx.facts` for cached hashes
3. For missing providers, runs terraform inline via `module_ctx.execute()`
4. Returns `extension_metadata(facts=new_hashes, reproducible=True)`
5. Bazel persists facts to `MODULE.bazel.lock`
