# Terraform Provider Management Architecture

## Overview

The Terraform provider management system supports incremental provider downloads at build time while maintaining reproducible builds through filesystem mirrors and proper caching.

**Key feature**: Provider hashes are automatically generated and cached in `MODULE.bazel.lock` via Bazel's module extension facts mechanism (requires Bazel 8.5+).

## Implementation Approach

### Provider Hash Generation

**Purpose**: Generate provider hashes (h1 and zh) automatically when new providers are added

**Process**:
1. Module extension reads provider requirements from `versions.json`
2. Checks `module_ctx.facts` for cached hashes
3. For missing providers, runs `terraform providers lock` inline
4. Parses `.terraform.lock.hcl` to extract hashes
5. Returns hashes via `extension_metadata(facts=...)` for caching

**Key Files**:
- `tf2/extensions.bzl` - Module extension with hash generation logic
- `tf2/providers/repository/hcl_parser.bzl` - Parses HCL lock files
- `tf2/providers/repository/terraform_providers.bzl` - Repository rule for provider registry

### Provider Download and Caching

**Purpose**: Download providers on-demand during build time and cache them efficiently

**Process**:
1. Module extension creates `provider_download_repository` entries for each provider/platform
2. Each repository downloads and extracts a single provider when needed
3. Providers are aggregated into a `filesystem_mirror` for Terraform to use
4. Terraform uses the filesystem mirror exclusively (no network access during builds)

**Key Files**:
- `tf2/providers/download/provider_download_repository.bzl` - Repository rule for downloading providers
- `tf2/providers/registry/filesystem_mirror.bzl` - BUILD rule for aggregating providers into mirror structure

## Architecture Components

### 1. Module Extension (`tf2/extensions.bzl`)

```python
def _tf_providers_impl(module_ctx):
    # Check cached hashes from facts
    has_facts = hasattr(module_ctx, "facts")

    # Read provider requirements from versions.json
    for mod in module_ctx.modules:
        for download in mod.tags.download:
            versions_data = json.decode(module_ctx.read(download.versions_file))

    # For each provider, check cache or generate hashes
    for provider_key in required_keys:
        cached = module_ctx.facts.get(provider_key, None) if has_facts else None
        if cached:
            new_hashes[provider_key] = cached
        else:
            # Generate hashes inline using terraform
            hashes = _generate_provider_hashes_inline(module_ctx, provider, version, tf_version)
            new_hashes[provider_key] = hashes

    # Create provider download repositories
    for provider, version in providers:
        provider_download_repository(name = "...", ...)

    # Return hashes for caching
    return module_ctx.extension_metadata(facts = new_hashes, reproducible = True)
```

### 2. Inline Hash Generation

```python
def _generate_provider_hashes_inline(module_ctx, provider_source, version, terraform_version):
    # Download terraform
    module_ctx.download_and_extract(url = terraform_url, output = terraform_dir)

    # Create terraform config
    module_ctx.file(work_dir.get_child("versions.tf"), versions_tf_content)

    # Run terraform init + providers lock
    module_ctx.execute([terraform_path, "init", "-backend=false"], working_directory = work_dir)
    module_ctx.execute([terraform_path, "providers", "lock", "-platform=linux_amd64", ...])

    # Parse lock file
    lock_content = module_ctx.read(work_dir.get_child(".terraform.lock.hcl"))
    return parse_lock_hcl(lock_content)
```

### 3. Provider Download Repository

```python
def _provider_download_repository_impl(repository_ctx):
    # Download provider binary using sha256 hash
    repository_ctx.download_and_extract(
        url = provider_url,
        sha256 = zh_hash,  # Uses zh hash for verification
        output = ".",
    )

    # Create BUILD.bazel exposing the provider
    repository_ctx.file("BUILD.bazel", ...)
```

### 4. Filesystem Mirror

```python
def _filesystem_mirror_impl(ctx):
    # Aggregate individual provider downloads
    # Create filesystem mirror structure:
    # registry.terraform.io/
    #   namespace/provider/version/platform/
    #     terraform-provider-name_vX.Y.Z
```

## How It Works

### Build Time Flow

1. **Provider Declaration**: User declares providers in `versions.json`
   ```json
   {
     "providers": {
       "hashicorp/aws": ["6.26.0"],
       "hashicorp/azurerm": ["4.56.0"]
     }
   }
   ```

2. **Hash Check**: Extension checks `module_ctx.facts` for cached hashes

3. **Hash Generation** (if needed): For missing providers, runs terraform inline to generate hashes

4. **Repository Creation**: Creates `provider_download_repository` for each provider/platform

5. **Module Declaration**: User declares providers in BUILD file
   ```python
   tf_module(
       name = "my_module",
       srcs = ["main.tf", "terraform.tf"],
       providers = [
           "@tf_provider_registry//:aws_6",
           "@tf_provider_registry//:azurerm_4",
       ],
   )
   ```

6. **Provider Resolution**: Build system resolves provider aliases to download targets

7. **Incremental Download**: Only downloads providers actually needed by the target being built

8. **Filesystem Mirror**: Aggregates downloaded providers into mirror structure

9. **Terraform Init**: Uses filesystem mirror with symlinks (no network access)
   ```hcl
   provider_installation {
     filesystem_mirror {
       path = "/path/to/mirror"
     }
   }
   ```

### Key Features

- **Automatic Hash Generation**: No manual scripts - hashes generated on first build
- **Persistent Caching**: Hashes cached in `MODULE.bazel.lock`, survive clean builds
- **Incremental Downloads**: Only fetches providers needed for specific builds
- **Bazel Caching**: Providers cached in Bazel's action cache
- **Network Isolation**: Terraform runs with network access disabled
- **Reproducible Builds**: Same inputs always produce same outputs
- **Platform Support**: Handles multiple OS/architecture combinations

## Provider Versioning

Providers are configured in `versions.json`:

```json
{
  "providers": {
    "hashicorp/aws": ["6.26.0"],
    "hashicorp/azurerm": ["4.56.0"],
    "paloaltonetworks/panos": ["2.0.5"]
  }
}
```

Provider aliases are automatically generated based on major version:
- `hashicorp/aws:6.26.0` → `@tf_provider_registry//:aws_6`
- `hashicorp/azurerm:4.56.0` → `@tf_provider_registry//:azurerm_4`

## Hash Storage

Hashes are stored in `MODULE.bazel.lock` under the facts section:

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

## Requirements

- **Bazel 8.5+**: Required for `module_ctx.facts` support
- **Network access**: Required only when generating hashes for new providers

## Testing

The system includes comprehensive tests:
- Validation tests verify Terraform can find and use providers
- Version check tests ensure terraform.tf matches provider declarations
- Format and lint tests maintain code quality
- Unit tests for HCL parsing (`//tests/unit/hcl_parser:hcl_parser_tests`)
