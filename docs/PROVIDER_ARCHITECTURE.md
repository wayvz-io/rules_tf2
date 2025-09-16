# Terraform Provider Management Architecture

## Overview

The Terraform provider management system supports incremental provider downloads at build time while maintaining reproducible builds through filesystem mirrors and proper caching.

## Implementation Approach

### Provider Download and Caching

**Purpose**: Download providers on-demand during build time and cache them efficiently

**Process**:
1. Module extension reads provider requirements from MODULE.bazel
2. Creates a single `terraform_providers` repository with all provider metadata
3. Repository generates BUILD file with individual `provider_download_action` targets
4. Each target downloads and extracts a single provider when needed
5. Providers are aggregated into a `filesystem_mirror` for Terraform to use
6. Terraform uses the filesystem mirror exclusively (no network access)

**Key Files**:
- `MODULE.bazel` - Declares provider versions to download
- `tf/extensions.bzl` - Module extension that creates provider repository
- `tf/core/repositories/terraform_providers.bzl` - Repository rule that generates BUILD file
- `tf/core/providers/provider_download_action.bzl` - BUILD rule for downloading individual providers
- `tf/core/providers/filesystem_mirror.bzl` - BUILD rule for aggregating providers into mirror structure

## Architecture Components

### 1. Module Extension (`tf/extensions.bzl`)

```python
def _tf_providers_impl(module_ctx):
    # Read provider requirements from MODULE.bazel
    for mod in module_ctx.modules:
        for download in mod.tags.download:
            providers.update(download.providers)
    
    # Create single repository with all provider metadata
    terraform_providers(
        name = "tf_provider_registry",
        providers = providers,
        # ... platform and architecture info
    )
```

### 2. Terraform Providers Repository (`terraform_providers.bzl`)

```python
def _terraform_providers_impl(ctx):
    # Generate BUILD file with download targets for each provider
    for provider, version, platform in providers:
        # Create provider_download_action target
        build_content.append('''
        provider_download_action(
            name = "download_{}_{}_{}_{}",
            provider = "{}",
            version = "{}",
            os = "{}",
            arch = "{}",
            url = "{}",
            sha256 = "{}",
        )
        ''')
    
    # Create filesystem_mirror that aggregates all providers
    build_content.append('''
    filesystem_mirror(
        name = "mirror_{}_{}", 
        providers = [":download_..."],
    )
    ''')
```

### 3. Provider Download Action (`provider_download_action.bzl`)

```python
def _provider_download_action_impl(ctx):
    # Download and extract single provider using shell script
    # Handles both HashiCorp direct downloads and registry API
    # Extracts provider binary to output directory
    # Returns directory with provider binary
```

### 4. Filesystem Mirror (`filesystem_mirror.bzl`)

```python
def _filesystem_mirror_impl(ctx):
    # Aggregate individual provider downloads
    # Create filesystem mirror structure:
    # registry.terraform.io/
    #   namespace/provider/version/platform/
    #     terraform-provider-name_vX.Y.Z
    # Terraform creates symlinks to this structure
```

## How It Works

### Build Time Flow

1. **Stack Declaration**: User declares providers in BUILD file
   ```python
   tf_stack(
       name = "my_stack",
       providers = [
           "@tf_provider_registry//:aws_6",
           "@tf_provider_registry//:azurerm_4",
       ],
   )
   ```

2. **Provider Resolution**: Build system resolves provider aliases to download targets

3. **Incremental Download**: Only downloads providers actually needed by the target being built

4. **Filesystem Mirror**: Aggregates downloaded providers into mirror structure

5. **Terraform Init**: Uses filesystem mirror with symlinks (no network access)
   ```hcl
   provider_installation {
     filesystem_mirror {
       path = "/path/to/mirror"
     }
   }
   ```

### Key Features

- **Incremental Downloads**: Only fetches providers needed for specific builds
- **Bazel Caching**: Providers cached in Bazel's action cache
- **Network Isolation**: Terraform runs with network access disabled
- **Reproducible Builds**: Same inputs always produce same outputs
- **Platform Support**: Handles multiple OS/architecture combinations

## Provider Versioning

Providers are versioned in MODULE.bazel:

```python
tf_providers = use_extension("@tf2//:tf", "providers")
tf_providers.download(
    providers = {
        "hashicorp/aws": ["6.12.0"],
        "hashicorp/azurerm": ["4.43.0"],
        "paloaltonetworks/panos": ["2.0.5"],
        # ...
    },
)
```

Provider aliases are automatically generated based on major version:
- `hashicorp/aws:6.12.0` → `@tf_provider_registry//:aws_6`
- `hashicorp/azurerm:4.43.0` → `@tf_provider_registry//:azurerm_4`

## Testing

The system includes comprehensive tests:
- Validation tests verify Terraform can find and use providers
- Version check tests ensure terraform.tf matches provider declarations
- Format and lint tests maintain code quality

## Future Enhancements

Potential improvements for consideration:
- Lock file generation and verification for provider hashes
- Support for provider signing verification
- Mirror pre-population for offline builds
- Provider version constraint resolution