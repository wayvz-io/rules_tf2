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
| `# gazelle:terraform_enabled <true\|false>` | Enable or disable generation for the directory (default: enabled) |
| `# gazelle:terraform_provider <provider_name> <label>` | Map a Terraform provider name to a provider registry label |
| `# gazelle:terraform_ignore_file_warning <filename>` | Suppress warnings for a file with a dynamic/unresolved path |

Example:

```starlark
# gazelle:terraform_provider aws @tf_provider_registry//:aws_6
# gazelle:terraform_ignore_file_warning generated.tf
```

## Generated Targets

For each directory containing `.tf` files, Gazelle generates a `tf_module` target and a
corresponding `tf_test` target. The `tf_module` target has:

- `name` defaulting to `tf_module` (the `tf_test` target defaults to `tf_test`), so a
  module is referenced as `//path/to/dir:tf_module`
- `srcs` containing all `.tf` files and `README.md`
- `deps` inferred from local module references
- `providers` mapped from `terraform_provider` directives or parent configuration
