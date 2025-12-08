# About Module Structure

## Overview

rules_tf2 tracks module relationships through the `deps` and `modules` attributes, and can automatically generate BUILD files via Gazelle.

## Module Dependencies

Terraform modules can reference other modules via relative paths (`source = "./modules/child"`). rules_tf2 needs to know these relationships to:

1. Build modules in the correct order
2. Include child module files when staging the parent
3. Inherit provider requirements up the tree
4. Invalidate caches when dependencies change

### deps vs modules

**deps** - For modules in separate directories:

```starlark
tf_module(
    name = "vpc",
    srcs = glob(["*.tf"]),
    deps = ["//iac/shared/tags"],  # separate directory
)
```

**modules** - For nested modules in subdirectories:

```starlark
tf_module(
    name = "vpc",
    srcs = glob(["*.tf"]),
    modules = [
        "//iac/network/vpc/modules/subnets",
        "//iac/network/vpc/modules/routes",
    ],
)
```

### Provider Inheritance

When module A depends on module B, A inherits B's provider requirements. The generated lockfile for A includes all providers from the entire dependency tree.

This means:
- Child modules don't need to redeclare providers the parent already has
- Parent modules automatically get providers their children need
- The lockfile stays consistent across the tree

## Gazelle

rules_tf2 includes a Gazelle extension that automatically generates `BUILD.bazel` files. Instead of writing `tf_module` declarations manually, Gazelle scans directories for `.tf` files and generates the rules.

### What Gazelle Generates

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

Gazelle generates explicit file lists rather than globs—Bazel knows exactly which files are included without scanning the filesystem.

### Test File Detection

When `.tftest.hcl` files are present, Gazelle generates a separate `tf_test` rule:

```starlark
tf_module(
    srcs = ["main.tf", "variables.tf"],
)

tf_test(
    module = ":tf_module",
    test_files = ["basic.tftest.hcl"],
)
```

### Provider Mapping

Configure provider detection via directives:

```starlark
# gazelle:terraform_provider aws @tf_provider_registry//:aws_5
```

Gazelle then parses `terraform.tf` and adds matching providers to the generated rule.

### Preserved Attributes

When updating existing rules, Gazelle preserves manually-set attributes like `providers`, `modules`, `visibility`, and `tags`.

## See Also

- [Providers](providers.md) - Provider inheritance details
- [Architecture](architecture.md)
