# Gazelle Extension

The `tf2_gazelle` extension auto-generates BUILD.bazel files for Terraform modules.

## Usage

```starlark
# WORKSPACE or MODULE.bazel
bazel_dep(name = "gazelle", version = "...")

# BUILD.bazel (repository root)
load("@gazelle//:def.bzl", "gazelle")

gazelle(
    name = "gazelle",
)
```

## Directives

Configure Gazelle behavior with directives in BUILD.bazel files:

| Directive | Description |
|-----------|-------------|
| `# gazelle:tf2_module_prefix` | Prefix for generated module names |
| `# gazelle:tf2_providers` | Default providers for generated modules |

## Generated Targets

For each directory containing `.tf` files, Gazelle generates a `tf_module` target with:

- `name` derived from directory name
- `srcs` containing all `.tf` files and `README.md`
- `deps` inferred from local module references
- `providers` from directive or parent configuration
