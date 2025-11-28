# Gazelle Extension for Terraform

A Gazelle language extension that automatically generates and maintains `BUILD.bazel` files for Terraform modules.

## Features

- Generates `tf_module` rules from directories containing `.tf` files
- Uses default name `tf_module` (no explicit name needed since 1 module per directory)
- Includes `README.md` in sources when present
- Supports provider mapping via directives
- Preserves manually-set attributes when updating existing rules

## Usage

Run Gazelle on your Terraform modules:

```bash
bazel run //tf2/gazelle:gazelle -- path/to/modules
```

Or run on the entire repository:

```bash
bazel run //tf2/gazelle:gazelle
```

## Generated Output

### Basic Module

Given a directory with `.tf` files:

```
modules/vpc/
├── main.tf
├── variables.tf
├── outputs.tf
└── terraform.tf
```

Gazelle generates:

```starlark
load("//tf2:def.bzl", "tf_module")

tf_module(
    srcs = glob(["*.tf"]),
)
```

Note: The `name` attribute defaults to `"tf_module"` and is omitted. Reference the module as `//modules/vpc:tf_module`.

### Module with README

When `README.md` is present, files are listed explicitly:

```starlark
tf_module(
    srcs = [
        "main.tf",
        "outputs.tf",
        "terraform.tf",
        "variables.tf",
        "README.md",
    ],
)
```

### Module with Tests

Test files (`.tftest.hcl`, `.tftest.json`) are handled automatically by the `tf_module` macro - no separate `tf_test` rule is needed.

## Directives

Configure the extension via BUILD file directives:

### terraform_enabled

Disable Gazelle for a directory:

```starlark
# gazelle:terraform_enabled false
```

### terraform_provider

Map provider names to registry labels:

```starlark
# gazelle:terraform_provider random @tf_provider_registry//:random_3
# gazelle:terraform_provider aws @tf_provider_registry//:aws_5
```

When configured, Gazelle parses `terraform.tf` and adds matching providers:

```starlark
tf_module(
    srcs = glob(["*.tf"]),
    providers = ["@tf_provider_registry//:aws_5"],
)
```

## Preserved Attributes

When updating existing rules, Gazelle preserves:

- `providers` (if not auto-detected)
- `modules`
- `tflint_config`
- `tfdoc_config`
- `visibility`
- `tags`
