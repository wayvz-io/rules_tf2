# Provider Versioning

## The Problem

Standard Terraform workflows have each tool manage its own provider cache:

- Terraform uses `.terraform/` directories
- TFLint downloads to `~/.tflint.d/`
- Other tools have their own mechanisms

This leads to duplicated downloads, inconsistent versions, and complex CI cache management.

## Unified Cache

rules_tf2 downloads providers once into Bazel's cache. All tools (terraform, tflint, etc.) use providers from this single location.

The `tf_providers` extension reads `versions.json`, verifies hashes against `provider_locks.json`, and creates download repositories for each provider/platform combination.

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

## Lock Files

### provider_locks.json

A centralized lockfile contains hashes for every provider version:

```json
{
  "hashicorp/aws:5.40.0": {
    "h1": ["..."],
    "zh": ["..."]
  }
}
```

JSON format is used because Starlark can parse it (unlike HCL).

### Per-Module .terraform.lock.hcl

Each module still needs `.terraform.lock.hcl` for Terraform. rules_tf2 generates these at build time from the subset of providers that module requires.

## Filesystem Mirrors

At build time, providers are assembled into a filesystem mirror:

```
.terraform/providers/
└── registry.terraform.io/
    └── hashicorp/
        └── aws/
            └── 5.40.0/
                └── linux_amd64/
                    └── terraform-provider-aws_v5.40.0
```

Terraform uses this without network access during execution.
