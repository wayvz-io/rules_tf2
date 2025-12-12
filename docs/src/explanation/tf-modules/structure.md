# Module Structure

## File Organization

A typical module:

```
modules/vpc/
├── BUILD.bazel
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tf      # provider requirements
└── README.md
```

The `srcs` attribute lists files included in the module:

```starlark
tf_module(
    srcs = [
        "main.tf",
        "outputs.tf",
        "README.md",
        "terraform.tf",
        "variables.tf",
    ],
)
```

Only files in `srcs` are staged for Terraform operations. Missing a file here means it won't be included.

## Why Not Globs?

Don't use `glob(["*.tf"])`. Explicit file lists ensure:

- **Correct cache invalidation** - Bazel knows exactly which files affect the build
- **Faster reloads** - Changes to unlisted files don't trigger rebuilds
- **No surprises** - Stray `.tf` files aren't accidentally included

Use [Gazelle](../versioning/gazelle.md) to generate and maintain file lists automatically.

## Module Dependencies

Terraform modules reference other modules via relative paths (`source = "../shared/tags"`). rules_tf2 needs these relationships declared for:

- Build ordering
- Staging child modules with parents
- Provider inheritance
- Cache invalidation

### deps vs modules

**deps** - Modules in separate directories:

```starlark
tf_module(
    name = "vpc",
    srcs = [
        "main.tf",
        "outputs.tf",
        "variables.tf",
    ],
    deps = ["//iac/shared/tags"],
)
```

**modules** - Nested modules in subdirectories:

```starlark
tf_module(
    name = "vpc",
    srcs = [
        "main.tf",
        "outputs.tf",
        "variables.tf",
    ],
    modules = [
        "//iac/network/vpc/modules/subnets",
        "//iac/network/vpc/modules/routes",
    ],
)
```

The distinction matters for staging—`modules` are copied into the parent's directory structure.

## Provider Inheritance

When module A depends on module B, A inherits B's provider requirements:

```
Module A (uses aws, depends on B)
└── Module B (uses aws, random)

A's effective providers: aws, random
```

The generated lockfile for A contains hashes for all providers in the tree. Child modules don't redeclare providers the parent already has.

## Providers Attribute

Declare providers the module directly uses:

```starlark
tf_module(
    name = "vpc",
    srcs = [
        "main.tf",
        "outputs.tf",
        "terraform.tf",
        "variables.tf",
    ],
    providers = [
        "@tf_provider_registry//:aws_5",
        "@tf_provider_registry//:random_3",
    ],
)
```

Provider aliases (`aws_5`, `random_3`) come from your `versions.json` configuration.

## See Also

- [tf_module Reference](../../reference/rules/tf-module.md) - Full attribute documentation
- [Gazelle](../versioning/gazelle.md) - Automatic BUILD file generation
