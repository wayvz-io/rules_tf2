# Gazelle Extension for Terraform

A Gazelle language extension that automatically generates and maintains `BUILD.bazel` files for Terraform modules.

## Features

- Generates `tf_module` rules from directories containing `.tf` files
- Generates `tf_test` rules when `.tftest.hcl` or `.tftest.json` files are present
- Uses explicit file lists (not glob) for deterministic builds
- Uses default name `tf_module` / `tf_test` (one per directory)
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
    srcs = [
        "main.tf",
        "outputs.tf",
        "terraform.tf",
        "variables.tf",
    ],
)
```

Note: The `name` attribute defaults to `"tf_module"` and is omitted. Reference the module as `//modules/vpc:tf_module`.

### Module with README

When `README.md` is present, it's included in the explicit file list:

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

### Module with Tests

When `.tftest.hcl` or `.tftest.json` files are present, Gazelle generates a separate `tf_test` rule:

```starlark
load("//tf2:def.bzl", "tf_module", "tf_test")

tf_module(
    srcs = [
        "main.tf",
        "outputs.tf",
        "terraform.tf",
        "variables.tf",
    ],
)

tf_test(
    module = ":tf_module",
    test_files = [
        "basic.tftest.hcl",
        "validation.tftest.hcl",
    ],
)
```

Note: Test files are kept separate from `tf_module.srcs` and only appear in `tf_test.test_files`.

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
    srcs = [
        "main.tf",
        "terraform.tf",
        "variables.tf",
    ],
    providers = ["@tf_provider_registry//:aws_5"],
)
```

### terraform_ignore_file_warning

Suppress the warning Gazelle emits when a `.tf` file references a path that cannot be resolved statically (for example a `${path.module}`-based dynamic path). Use this for files that only exist at runtime:

```starlark
# gazelle:terraform_ignore_file_warning generated.tf
```

## Preserved Attributes

When updating existing rules, Gazelle preserves:

- `providers` (if not auto-detected)
- `modules`
- `tflint_config`
- `tfdoc_config`
- `visibility`
- `skip_validation`
- `tags`
- `testonly`
