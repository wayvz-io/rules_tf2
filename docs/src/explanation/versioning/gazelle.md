# Gazelle

rules_tf2 includes a Gazelle extension that generates `BUILD.bazel` files from Terraform directories. Instead of writing `tf_module` declarations manually, Gazelle scans for `.tf` files and creates them.

## Running Gazelle

```bash
bazel run //tf2/gazelle:gazelle -- path/to/modules
```

Gazelle walks the directory tree, finds Terraform files, and generates or updates BUILD files.

## What Gets Generated

Given a directory:

```
modules/vpc/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md
```

Gazelle generates:

```starlark
tf_module(
    srcs = [
        "main.tf",
        "outputs.tf",
        "README.md",
        "variables.tf",
    ],
)
```

Explicit file lists rather than globs—Bazel knows exactly which files are included.

## Test File Detection

When `.tftest.hcl` files are present, Gazelle generates a `tf_test` rule:

```starlark
tf_module(
    srcs = ["main.tf", "variables.tf"],
)

tf_test(
    module = ":tf_module",
    test_files = ["basic.tftest.hcl"],
)
```

## Provider Mapping

Configure provider detection with directives in BUILD files:

```starlark
# gazelle:terraform_provider aws @tf_provider_registry//:aws_5
```

Gazelle parses `terraform.tf` and adds matching providers to generated rules.

## Preserved Attributes

When updating existing rules, Gazelle preserves manually-set attributes:
- `providers`
- `modules`
- `deps`
- `visibility`
- `tags`

Manual overrides aren't lost on regeneration.

## Directives

| Directive | Effect |
|-----------|--------|
| `# gazelle:terraform_enabled false` | Disable for directory |
| `# gazelle:terraform_provider NAME TARGET` | Map provider to registry alias |
| `# gazelle:terraform_ignore_file_warning FILENAME` | Suppress the "referenced with dynamic path" warning for a file that only exists at runtime |

## When to Run

Run Gazelle after:
- Adding new Terraform modules
- Adding/removing `.tf` files
- Updating provider versions (to refresh provider declarations)
- Structural changes to module directories

For module structure and dependency details, see [Terraform Modules](../tf-modules/README.md).
