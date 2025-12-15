# Provider Versioning

## The Problem

Standard Terraform workflows have each tool manage its own provider cache:

- Terraform uses `.terraform/` directories
- TFLint downloads to `~/.tflint.d/`
- Other tools have their own mechanisms

This leads to duplicated downloads, inconsistent versions, and complex CI cache management.

## Unified Cache

rules_tf2 downloads providers once into Bazel's cache. All tools (terraform, tflint, etc.) use providers from this single location.

The `tf_providers` extension reads `versions.json`, automatically generates hashes (cached in `MODULE.bazel.lock`), and creates download repositories for each provider/platform combination.

## Major Version Aliasing

Providers are aliased by major version:

| Provider | Alias |
|----------|-------|
| hashicorp/aws 5.x.x | `aws_5` |
| hashicorp/aws 6.x.x | `aws_6` |
| hashicorp/azurerm 4.x.x | `azurerm_4` |
| hashicorp/time 0.x.x | `time_0` |

For 0.x providers, semver allows breaking changes between minor versions, so the alias reflects that.

Multiple versions can coexist—useful when migrating between major versions:

```json
"hashicorp/aws": ["5.40.0", "6.0.0"]
```

Reference as `@tf_provider_registry//:aws_5` or `@tf_provider_registry//:aws_6`.

## Provider Inheritance

When module A depends on module B, A inherits B's provider requirements. The generated lockfile for A includes all providers from the dependency tree.

Parent modules don't redeclare providers their children use—they're inherited automatically.

## Lock Files and Hashes

### Automatic Hash Generation

Provider hashes (h1 and zh) are **automatically generated** when you add a new provider to `versions.json`. The `tf_providers` extension:

1. Detects providers missing from the cache (via `module_ctx.facts`)
2. Downloads terraform and runs `terraform providers lock` for all platforms
3. Parses the generated `.terraform.lock.hcl` to extract hashes
4. Stores hashes in `MODULE.bazel.lock` (Bazel's lockfile)

This happens transparently on `bazel build` - no manual scripts required.

### MODULE.bazel.lock

Hashes are stored in Bazel's lockfile under the facts section:

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

This file should be committed to version control. It ensures reproducible builds and avoids re-generating hashes on every machine.

### Per-Module .terraform.lock.hcl

Each module still needs `.terraform.lock.hcl` for Terraform. rules_tf2 generates these at build time from the subset of providers that module requires, using hashes from `@tf_provider_registry//:provider_locks.json`.

## Filesystem Mirrors

At build time, providers are assembled into a filesystem mirror:

```
.terraform/providers/
└── registry.terraform.io/
    └── hashicorp/
        └── aws/
            └── 6.26.0/
                └── linux_amd64/
                    └── terraform-provider-aws_v6.26.0
```

Terraform uses this without network access during execution.

## Updating Providers

```bash
# 1. Update versions.json (manually or via script)
./scripts/tf_upgrade_providers.sh

# 2. Build to generate hashes for new versions
bazel build //...

# 3. Test
bazel test //...

# 4. Commit both files
git add versions.json MODULE.bazel.lock
git commit -m "Update provider versions"
```

## Requirements

- **Bazel 8.5+**: Required for `module_ctx.facts` support
- **Network access**: Required only when generating hashes for new providers (one-time per provider version)
