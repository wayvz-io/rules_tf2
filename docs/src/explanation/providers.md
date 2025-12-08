# About Provider System

## Overview

rules_tf2 manages Terraform providers through a centralized registry system.

## The Problem with Tool-Specific Caching

In standard Terraform workflows, each tool manages its own provider cache:

- **Terraform** uses `.terraform/` directories and plugin caches
- **TFLint** downloads plugins to `~/.tflint.d/`
- **Other tools** have their own caching mechanisms

Each tool configures caching differently, leading to duplicated downloads, inconsistent versions between tools, and complex cache management across CI environments.

## How rules_tf2 Solves This

The registry system provides a single source of truth for providers:

1. **Unified cache**: All tools (terraform, tflint, etc.) use providers from the same Bazel-managed cache
2. **On-demand downloading**: Providers are downloaded only when needed for a specific test or action, but once cached, they're never re-downloaded
3. **Consistent lockfiles**: One centralized lockfile governs provider versions across all modules, enabling coordinated updates and verification that everything works together

> This means re-implementing Terraform's native provider downloading within Bazel—the trade-off for bringing everything into a single build system.

## How Provider Downloads Work

### Configuration

Providers are configured in `versions.json`:

```json
{
  "providers": {
    "aws": "5.0.0",
    "random": "3.6.0"
  }
}
```

### Download Process

The `tf_providers` module extension:

1. Reads `versions.json` for provider versions
2. Reads `provider_locks.json` for hash verification
3. Creates repository rules for each provider/platform combination
4. Aggregates into `tf_provider_registry` repository

### Repository Structure

For each provider:
```
tf_provider_aws_5_0_0_linux_amd64/
  └── terraform-provider-aws_v5.0.0
```

The registry aggregates these:
```
tf_provider_registry/
  ├── aws_5 → @tf_provider_aws_5_0_0_{platform}
  └── random_3 → @tf_provider_random_3_6_0_{platform}
```

## Provider Aliasing

Providers are aliased by major version following semver—breaking changes only happen at major version boundaries:

| Provider | Alias |
|----------|-------|
| hashicorp/aws 5.x.x | `aws_5` |
| hashicorp/azurerm 4.x.x | `azurerm_4` |
| hashicorp/time 0.x.x | `time_0` |

For 0.x providers, semver allows breaking changes between minor versions, so the alias reflects that.

## Provider Inheritance

When module A depends on module B, module A inherits B's provider requirements:

```
Module A (uses aws, depends on B)
└── Module B (uses aws, random)

A's effective providers: aws, random
```

This means parent modules don't need to explicitly declare providers used only by their dependencies. The lock file for A will contain hashes for all providers in the dependency tree.

## Lock Files

### The Megalockfile Approach

rules_tf2 uses a centralized "megalockfile" (`provider_locks.json`) that contains hashes for every provider. This is generated once when you update provider versions, then loaded into Bazel's repository rules.

### Format

```json
{
  "hashicorp/aws": {
    "version": "5.0.0",
    "platforms": {
      "linux_amd64": {
        "hash": "h1:...",
        "zh_hash": "zh:..."
      }
    }
  }
}
```

### Per-Module Lockfiles

While the megalockfile manages the source of truth, each Terraform workspace still needs a `.terraform.lock.hcl` file. rules_tf2 generates these automatically during builds, using only the subset of providers that module actually requires.

> We use JSON rather than Terraform's native `.terraform.lock.hcl` for the megalockfile because JSON is parseable in Starlark.

## Filesystem Mirrors

At build time, providers are assembled into a filesystem mirror structure that Terraform recognizes:

```
.terraform/providers/
└── registry.terraform.io/
    └── hashicorp/
        └── aws/
            └── 5.0.0/
                └── linux_amd64/
                    └── terraform-provider-aws_v5.0.0
```

This allows Terraform to use providers without network access during execution.

## See Also

- [Architecture](architecture.md) - Overall system design
- [provider_mirror Reference](../reference/providers/provider-mirror.md) - Rule documentation
