# tf_stack

Macro for creating Terraform Stacks with comprehensive testing and module staging.

## Overview

`tf_stack` creates a Terraform Stack target that:
- Aggregates providers from all referenced `tf_module` targets
- Stages modules to `./components/` directory structure
- Generates lockfile and `.terraform-version` file
- Creates format, validate, and dependency tests

## Usage

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_stack")

tf_stack(
    name = "my_stack",
    srcs = [
        "components.tfcomponent.hcl",
        "providers.tfcomponent.hcl",
        "variables.tfcomponent.hcl",
        "dev.tfdeploy.hcl",
    ],
    modules = [
        "//path/to/module:tf_module",
    ],
)
```

## Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | string | Stack name (default: "tf_stack") |
| `srcs` | label_list | Stack source files (.tfcomponent.hcl, .tfdeploy.hcl, .json) |
| `modules` | label_list | tf_module targets referenced by components |
| `providers` | label_list | Additional provider_mirror targets (optional) |
| `terraform_version` | string | Terraform version (default: "1.14.1") |
| `skip_validation` | bool | Skip terraform stacks validate test |
| `visibility` | string_list | Visibility specification |
| `tags` | string_list | Tags for test targets |

## Generated Targets

For `tf_stack(name = "my_stack")`:

| Target | Description |
|--------|-------------|
| `:my_stack` | Main stack (TfStackInfo provider) |
| `:my_stack_srcs` | Filegroup of all sources |
| `:my_stack_format_test` | Check HCL formatting |
| `:my_stack_format` | Fix HCL formatting |
| `:my_stack_validate_test` | Run `terraform stacks validate` |
| `:my_stack_deps_test` | Verify modules match component sources |
| `:my_stack_untracked_files_test` | Check for untracked files |
| `:my_stack_file_export` | Export to directory |
| `:my_stack_generate_versions` | Report provider versions (for tf-update workflow) |

## Module Staging

Referenced modules are staged to the `./components/` directory:

```
exported_stack/
├── *.tfcomponent.hcl          # Component files at root
├── *.tfdeploy.hcl             # Deploy files at root
├── components/                 # Staged modules
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tf
│   └── eks/
│       └── ...
├── .terraform.lock.hcl        # Generated lockfile
└── .terraform-version         # Generated version file
```

## Provider Inheritance

Providers are automatically collected from all referenced `tf_module` targets. The lockfile includes all transitive providers.

## Updating Provider Versions

When provider versions change in `versions.json`, run the tf-update workflow:

```bash
# Update all provider versions (modules and stacks)
bazel run //:tf-update

# Or run individual steps:
bazel run //:tf-upgrade-providers  # Check for version updates
bazel run //:tf-mod                 # Regenerate locks and terraform.tf files
```

The `tf-mod` command runs `tf_regenerate_all` which queries for `*_generate_versions` targets. Stack targets are included in this query and report their provider configuration:

```bash
# View stack provider configuration
bazel run //path/to:stack_generate_versions
```

Since stacks inherit providers from modules, updating modules automatically updates stack provider configurations. The stack's lockfile is regenerated from the updated module providers.

## Exporting Stacks

Use the `_file_export` target to export a stack:

```bash
bazel run //path/to:stack_file_export -- /path/to/output
```

## Requirements

The `terraform stacks` commands require:
- Terraform >= 1.13.0 with Stacks support
- HCP Terraform account for `terraform stacks validate` and `terraform stacks fmt`

**Note**: The format and validate tests require the HCP Terraform stacks plugin. For local development without HCP Terraform, use `skip_validation = True`.

## Example

```starlark
# BUILD.bazel
load("@rules_tf2//tf2:def.bzl", "tf_stack", "tf_module")

# Template modules
tf_module(
    name = "vpc",
    srcs = [
        "components/vpc/main.tf",
        "components/vpc/outputs.tf",
        "components/vpc/variables.tf",
    ],
    providers = ["@tf_provider_registry//:aws_6"],
)

tf_module(
    name = "eks",
    srcs = [
        "components/eks/main.tf",
        "components/eks/outputs.tf",
        "components/eks/variables.tf",
    ],
    providers = ["@tf_provider_registry//:aws_6"],
    modules = [":vpc"],
)

# The stack
tf_stack(
    name = "infra_stack",
    srcs = [
        "components.tfcomponent.hcl",
        "providers.tfcomponent.hcl",
        "dev.tfdeploy.hcl",
    ],
    modules = [":vpc", ":eks"],
)
```

See [Rules Overview](README.md) for more information.
